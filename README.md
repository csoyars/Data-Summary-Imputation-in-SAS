# Data-Summary-Imputation-in-SAS
A SAS macro written to assist in evaluating and if necessary imputing observations in large, potentially messy datasets with many variables.

This macro was developed for use in cleaning a financial dataset containing many missing or coded values across several hundred variables. It represents my first experience and independent efforts in learning to read and write SAS macros, with functionality intended to replicate and improve on supplied code while completing the assigned task in a fraction of the time required previously. The macro is easily adapted to other datasets with different parameters, including or excluding any use of coded values.

If PCTREM=1, the macro logs selected summary statistics for each variable along with information on proportion of missing or coded values without imputing or dropping any values. Otherwise, the macro will impute missing, coded, and extreme observations (as defined by user's MSTD threshold) and drop any variables with proportion of missing/coded values above the defined PCTREM value.

Values are imputed to the median for each variable, again as per previously supplied code and parameters. The macro is readily adaptible to use with other imputation methods given the split functionality depending on PCTREM value.
