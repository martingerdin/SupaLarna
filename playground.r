## This is a file for testing

## Source all functions (remove when turned into package)
files <- list.files("./R", pattern = ".r$", full.names = TRUE)
for (f in files) source(f)
## Set parameters that are default in make.study
data_path =  c("./extdata/sample.csv")
bs_samples = 4

## Code below this line is more or less a copy of make.study. Make sure to
## modify make.study if you modify important stuff here.

##----------------------------------------------------------------------------##

## Set seed
set.seed(14813)
## Load all required packages (remove when turned into package)
load.required.packages()
## Import study data
study_data <- read.csv(data_path, stringsAsFactors = FALSE)
## Drop obsevations collected before all centres started collecting triage
## category data and observations later than one month prior to creating
## this dataset
study_data <- drop.observations(study_data, test = TRUE)
## Get data dictionary
data_dictionary <- get.data.dictionary()
## Keep only variables relevant to this study
study_data <- keep.relevant.variables(study_data, data_dictionary)
## Define 999 as missing
study_data[study_data == 999] <- NA
## Prepare study data using the data dictionary
study_data <- prepare.study.data(study_data, data_dictionary, test = TRUE)
## Set patients to dead if dead at discharge or at 24 hours
## and alive if coded alive and admitted to other hospital
study_data <- set.to.outcome(study_data)
## Replace age >89 with 90 and make age numeric
study_data$age[study_data$age == ">89"] <- "90"
study_data$age <- as.numeric(study_data$age)
## Collapse mechanism of injury
study_data <- collapse.moi(study_data)
## Add time between injury and arrival and drop date and time variables from
## study data
study_data <- add.time.between.injury.and.arrival(study_data, data_dictionary)
## Apply exclusion criteria, i.e. drop observations with missing outcome
## data and save exclusions to results list
results <- list() # List to hold results
study_data <- apply.exclusion.criteria(study_data)
## Create missing indicator variables and save table of number of missing
## values per variable
study_data <- add.missing.indicator.variables(study_data)
## Prepare data for SuperLearner predictions
prepped_sample <- prep.data.for.superlearner(study_data, test = TRUE)
## Create table of sample characteristics
tables <- create.table.of.sample.characteristics(prepped_sample, data_dictionary)
results$table_of_sample_characteristics <- tables$formatted
results$raw_table_of_sample_characteristics <- tables$raw
results$n_training_sample <- nrow(prepped_sample$x_train)
results$n_test_sample <- nrow(prepped_sample$x_review)
## Transform factors into dummy variables
prepped_sample <- to.dummy.variables(prepped_sample)
## Save original sample to disk
saveRDS(prepped_sample, "original_sample.rds")
## Train and review SuperLearner on study sample. Remember to consider changing
## the sample setting in gridsearching for optimal cutpoints.
study_sample <- predictions.with.superlearner(prepped_sample,
                                              save_breaks = TRUE,
                                              save_all_predictions = TRUE,
                                              save_superlearner = TRUE,
                                              sample = FALSE,
                                              gridsearch_parallel = TRUE,
                                              n_cores = 4,
                                              log = TRUE,
                                              write_to_disk = TRUE,
                                              clean_start = TRUE)
## Save point estimates to disk
saveRDS(study_sample, "point_estimates.rds")
## Bootstrap samples
bootstrap_samples <- generate.bootstrap.samples(study_data,
                                      bs_samples)
## Prepare samples
prepped_samples <- prep.bssamples(bootstrap_samples)
## Save prepped samples to disk
saveRDS(prepped_samples, "bootstrap_samples.rds")
## Train and review SuperLearner on boostrap samples
samples <- train.predict.bssamples(prepped_samples,
                                   parallel = TRUE,
                                   n_cores = 4,
                                   log = TRUE,
                                   boot = TRUE,
                                   write_to_disk = TRUE)
## Save bootstrapped estimates
saveRDS(samples, "bootstrapped_estimates.rds")
## Create list of analyses to conduct
### Base analysis settings
base <- list(study_sample = study_sample,
             outcome = "outcome_test")
### Define main auc analysis
auc_main <- c(list(func = 'model.review.AUROCC',
                 model_or_pe = c("tc", "pred_cat_test"),
                 diffci_or_ci = "diff"),
              base)
### And main nri analysis
nri_main <- c(list(func = 'model.review.reclassification',
                 model_or_pe = c("NRI+", "NRI-"),
                 diffci_or_ci = "ci"),
              base)
### Define analysis to get point estimates from training set
auc_train <- auc_main
auc_train$model_or_pe <- c("pred_con_train", "pred_cat_train")
auc_train$diffci_or_ci <- "none"
auc_train$outcome <- "outcome_train"
### And analysis to get point estimate of pred_con in test set
auc_test <- auc_main
auc_test$model_or_pe <- "pred_con_test"
auc_test$diffci_or_ci <- "none"
### Put all analysis in one list
funcList <- list(auc_main = auc_main,
                 nri_main = nri_main,
                 auc_train = auc_train,
                 auc_test = auc_test)
## Generate confidence intervals around point estimates from funcList
pe_and_ci <- lapply(funcList,
                    function(i) generate.confidence.intervals(study_sample = study_sample,
                                                              func = get(i$func),
                                                              model_or_pointestimate = i$model_or_pe,
                                                              samples = samples,
                                                              diffci_or_ci = i$diffci_or_ci,
                                                              outcome_name = i$outcome))
## Extract from pe_and_ci and put in results
results <- c(results, extract.from.pe.and.ci(pe_and_ci))
## Create classification tables
results <- c(results, create.classification.tables(study_sample))
## Create roc plots
#create.roc.plots(study_sample)
## Alternative
create.ROCR.plots(study_sample, "ROC")
## Create roc plots for all models
create.ROCR.all(study_sample)
## Create precision/recall curve
create.ROCR.plots(study_sample, "prec_rec")
## Create calibration plots
create.calibration.plots(study_sample)
## Create mortality plot
create.mortality.plot(study_sample)
## Generate coefficiets table for all models
coefficients.table(study_sample)
## Save results to disk
saveRDS(results, "results.rds")
## Compile manuscript
#compile.manuscript("superlearner_vs_clinicians_manuscript")
