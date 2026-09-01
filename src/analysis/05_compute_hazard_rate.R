#######################################
######### Rate Ratio Analysis #########
#######################################

library(dplyr)
library(ggplot2)
library(scales)
library(emmeans)
library(broom)
library(purrr)
library(tidyr)
library(MASS)
library(splines)

# Load data
project_folder <- "<PATH/TO/PROJECT/FOLDER>"
mtbs_access        <- read.csv(file.path(project_folder, "/data/tables/mtbs_nfs_access_class_summary.csv"))
area               <- read.csv(file.path(project_folder, "/data/tables/nfs_access_extent_km2.csv"))
area

#Denominators by access (masked; sum across all states)
area_all <- area %>%
  mutate(access = recode(access_class,
                         "roadless"   = "IRA",
                         "wilderness" = "Wilderness",
                         "roaded"     = "Developed")) %>%
  group_by(access) %>%
  summarise(denom = sum(extent_masked_km2, na.rm = TRUE), .groups = "drop") %>%
  mutate(access = factor(access, levels = c("Developed","IRA","Wilderness")))

#Burned area per year × access (MTBS classes 1–4 only)
burned_by_year <- mtbs_access %>%
  filter(mtbs_class %in% 1:4) %>%
  group_by(year, access) %>%
  summarise(area_burned = sum(area_km2, na.rm = TRUE), .groups = "drop") %>%
  mutate(access = recode(access,
            "roadless"   = "IRA",
            "wilderness" = "Wilderness",
            "roaded"     = "Developed"),
      access = factor(access, levels = c("Developed","IRA","Wilderness")))

#Join denominators and compute annual burn rate
rates_by_year <- burned_by_year %>%
  filter(year >= 1984, year <= 2023) %>%
  left_join(area_all, by = "access") %>%
  mutate(
    burn_rate = area_burned / denom,
    exposure  = pmax(denom, 1)
  ) %>%
  rename(
    at_risk     = exposure
  )

#Check
area_all
rates_by_year %>% summarise(any_na_denom = any(is.na(denom)), min_year=min(year), max_year=max(year))

# Exposure-aware burn RATE model
# - Model numerator (area burned) with an exposure offset
# - Coefs exponentiate to rate ratios
# - quasipoisson handles overdispersion

rates_by_year <- rates_by_year %>% mutate(log_denom = log(denom))

m_access <- glm(
  area_burned ~ access,
  offset = log_denom,
  family = quasipoisson(link = "log"),
  data = rates_by_year
)

m_access_t <- glm(
  area_burned ~ access + ns(year, df = 2),
  offset = log_denom,
  family = quasipoisson(link = "log"),
  data = rates_by_year
)

print(summary(m_access))
print(summary(m_access_t))

#Get ratio rates and CIs directly from the model coefficients/VCOV (I couldn't seem to get emmeans to work)
rr_table <- function(fit) {
  b  <- coef(fit)
  V  <- vcov(fit)
  df <- df.residual(fit)
  tcrit <- qt(0.975, df)
  
  # differences on the log scale
  d_ira_dev <- b["accessIRA"]
  d_wil_dev <- b["accessWilderness"]
  d_wil_ira <- b["accessWilderness"] - b["accessIRA"]
  
  se_ira_dev <- sqrt(V["accessIRA","accessIRA"])
  se_wil_dev <- sqrt(V["accessWilderness","accessWilderness"])
  se_wil_ira <- sqrt(
    V["accessWilderness","accessWilderness"] +
      V["accessIRA","accessIRA"] -
      2*V["accessWilderness","accessIRA"]
  )
  
  tibble::tibble(
    contrast = c("IRA / Developed", "Wilderness / Developed", "Wilderness / IRA"),
    RR       = exp(c(d_ira_dev, d_wil_dev, d_wil_ira)),
    lower    = exp(c(d_ira_dev, d_wil_dev, d_wil_ira) - tcrit*c(se_ira_dev, se_wil_dev, se_wil_ira)),
    upper    = exp(c(d_ira_dev, d_wil_dev, d_wil_ira) + tcrit*c(se_ira_dev, se_wil_dev, se_wil_ira))
  )
}

rr_table(m_access)
rr_table(m_access_t)

#Bootstrap over years
#A) Nonparametric weighted means & differences
#B) Model-based bootstrap of emmeans differences

set.seed(123)

years   <- sort(unique(rates_by_year$year))
n_years <- length(years)

#1 = simple year bootstrap; use 3–5 for moving-block bootstrap
block_len <- 1

.sample_years <- function() {
  if (block_len <= 1) {
    sample(years, size = n_years, replace = TRUE)
  } else {
    starts <- sample(1:(n_years - block_len + 1),
                     size = ceiling(n_years / block_len),
                     replace = TRUE)
    yrs <- unlist(lapply(starts, function(s) years[s:(s + block_len - 1)]))
    yrs[1:n_years]
  }
}

#Resample rows by year with multiplicity (duplicates replicate rows)
.resample_rows_by_year <- function(df, yrs) {
  idx <- split(seq_len(nrow(df)), df$year)                 # row indices grouped by year
  keep <- unlist(idx[as.character(yrs)], use.names = FALSE) # repeats years => repeats rows
  df[keep, , drop = FALSE]
}

#A) Nonparametric: weighted mean burn ratios & pairwise differences
.compute_means_and_diffs <- function(df) {
  by_access <- df %>%
    group_by(access) %>%
    summarise(
      mean_rate = sum(area_burned, na.rm = TRUE) / sum(at_risk, na.rm = TRUE),
      .groups = "drop") %>%
    tidyr::complete(access = levels(rates_by_year$access), fill = list(mean_rate = NA_real_)) %>%
    tidyr::pivot_wider(names_from = access, values_from = mean_rate)
  
  tibble(
    mean_dev = by_access$Developed,
    mean_ira = by_access$IRA,
    mean_wil = by_access$Wilderness,
    diff_wil_minus_dev = by_access$Wilderness - by_access$Developed,
    diff_ira_minus_dev = by_access$IRA        - by_access$Developed,
    diff_wil_minus_ira = by_access$Wilderness - by_access$IRA
  )
}

obs_np <- .compute_means_and_diffs(rates_by_year)

R <- 5000
boot_np <- map_dfr(1:R, function(i) {
  yrs <- .sample_years()
  dfb <- .resample_rows_by_year(rates_by_year, yrs)
  .compute_means_and_diffs(dfb)
})

obs_model <- rr_table(m_access) %>%
  dplyr::select(contrast, RR) %>%   # <-- critical: drop lower/upper
  tidyr::pivot_wider(names_from = contrast, values_from = RR) %>%
  dplyr::rename(
    rr_ira_vs_dev = `IRA / Developed`,
    rr_wil_vs_dev = `Wilderness / Developed`,
    rr_wil_vs_ira = `Wilderness / IRA`
  )

names(obs_model)
obs_model

#B) Model-based bootstrap of differences
boot_model <- map_dfr(1:R, function(i) {
  yrs <- .sample_years()
  dfb <- .resample_rows_by_year(rates_by_year, yrs)
  
  # refit access-only offset model on the bootstrap sample
  fitb <- glm(
    area_burned ~ access,
    offset = log(denom),
    family = quasipoisson(link = "log"),
    data = dfb
  )
  
  rr_table(fitb) %>%
    dplyr::select(contrast, RR) %>%   # <-- critical: drop lower/upper
    tidyr::pivot_wider(names_from = contrast, values_from = RR) %>%
    dplyr::rename(
      rr_ira_vs_dev = `IRA / Developed`,
      rr_wil_vs_dev = `Wilderness / Developed`,
      rr_wil_vs_ira = `Wilderness / IRA`
    )
})

#Percentile CI summaries (no list-cols)
summarise_cis <- function(df) {
  df %>%
    summarise(
      across(
        everything(),
        list(
          lower  = ~ quantile(.x, 0.025, na.rm = TRUE),
          median = ~ quantile(.x, 0.500, na.rm = TRUE),
          upper  = ~ quantile(.x, 0.975, na.rm = TRUE)
        ),
        .names = "{.col}.{.fn}"
      )
    ) %>%
    tidyr::pivot_longer(
      everything(),
      names_to   = c("metric","stat"),
      names_sep  = "//.",
      values_to  = "value"
    ) %>%
    tidyr::pivot_wider(names_from = stat, values_from = value) %>%
    arrange(metric)
}

boot_np_summary    <- summarise_cis(boot_np)
boot_model_summary <- summarise_cis(boot_model)

#Print summaries
cat("/n=== Observed weighted mean burn ratios & differences (nonparametric) ===/n")
print(obs_np)

cat("/n=== Bootstrap percentile CIs (nonparametric, ",
    ifelse(block_len>1, paste0('moving-block, B=',block_len), "year"),
    ") ===/n", sep = "")
print(boot_np_summary)

cat("/n=== Observed rate ratios (model-based offset GLM) ===/n")
print(obs_model)

cat("/n=== Bootstrap percentile CIs (rate ratios; model-based) ===/n")
print(boot_model_summary)
