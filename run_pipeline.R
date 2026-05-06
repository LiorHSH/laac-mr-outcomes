## This script is designed to create two basic tables, containing the baseline characteristics and complication in two 
# subgroup of a selected population from NIH database, and to test weather changes in complication rates are robust to multivariate logistic regression.
# if the database structure changes, if you wish to run a similar analysis on a different database,
# or if you need to apply changes to the analysis method please note that you will hate to apply changes to this scripts.
#changes can be easily applied, yet, basic code requirements have to be maintained.

#Following segment installs required libraries. You only have to run in once on each computer
install.packages("haven")
install.packages("dplyr")
install.packages("tidyverse")
install.packages("stringr")
install.packages("reshape2")
install.packages("ggplot2")
#Following segment imports libraries. You have to run it every new R-session.
library("dplyr")
library("haven")
library("tidyverse")
library("stringr")
library("reshape2")
library("ggplot2")

Subset_Condition_Name = "MR" #Please change with regards to your project
IDX_Varaibles <- c("CHA2DS2_VASc", "Atria_Bleeding_Score","Charlson_Index")

## Make sure to change file info here:
#You can also set working directory using the following command:
# setwd(YOUR_FOLDER_PATH_HERE).
## You MUST change working directory BEFORE running next command.
current_data <- read_sav("LAAC_ANY_2016_2021.sav")  #SAV file name

#This file contains all background info ICD10 codes (including background info that is only used to calculate index values).
Background_Info_DF <- read.csv("Background_Info.csv")

# Excluding patients < 18 :
print(nrow(current_data)) # number of rows before eliminating children
print(sum(current_data["DISCWT"])) # number of weighted rows before eliminating children
current_data = current_data %>%
  filter(current_data$AGE >= 18)
print(nrow(current_data)) # number of rows after eliminating children
print(sum(current_data["DISCWT"])) # number of  weighted rows after eliminating children

# percentage of missing values per columns
# Example: assuming your data frame is called df
cols <- c("FEMALE", "RACE", "ZIPINC_QRTL", "LOS", "DIED")
missing_table <- data.frame(
  Column = cols,
  Missing_Percent = sapply(current_data[cols], function(x) sum(is.na(x)) )
)

print(missing_table)



#Excluding Missing Values:
current_data = current_data %>%
  drop_na(c("FEMALE", "RACE", "ZIPINC_QRTL","LOS", "DIED"))
print(nrow(current_data)) # number of rows after eliminating patients with missing data
print(sum(current_data["DISCWT"])) #number of weighted rows after eliminating patients with missing data

#Changing Columns Names:
names(current_data)[names(current_data)=="LOS"] <- "Length_of_Stay"
names(current_data)[names(current_data)=="DIED"] <- "Mortality"

## Creating a vector of characteristics to present on table 1. More characteristics are added next segment.
Table1_Categorical_Variables <- c("FEMALE", "White_Ethnicity_Rate")

#Adding columns of background info. DO NOT RUN if background_info_DF is not properly loaded to current environment.
for (i in 1:nrow(Background_Info_DF)){
  Background_Values <- str_split_1(Background_Info_DF[i,2], ",")
  current_data = current_data %>%
    mutate(New_Column = case_when(if_any(starts_with("I10_DX"),~.x %in% Background_Values ) ~1, .default = 0))
  names(current_data)[names(current_data) == "New_Column"] <- Background_Info_DF[i,1]
  if (Background_Info_DF[i, 3] == 1){
    Table1_Categorical_Variables <- append(Table1_Categorical_Variables, Background_Info_DF[i,1])
  }
}

#Adding more characteristics to be presented in Table1
Table1_Categorical_Variables <- append(Table1_Categorical_Variables, c("Median_Income_Quartile", "Hospital_Type")
                                      , after = length(Table1_Categorical_Variables))

## Calculating Index variables:
current_data = current_data %>%
  mutate(
    CHA2DS2_VASc =  case_when(AGE >= 75 ~ 2, AGE <65 ~0, AGE > 65 & AGE < 74 ~ 1, .default = 0 )  + FEMALE 
    + Congestive_Heart_Failure + Hypertension + Diabetes + Stroke_TIA_Thromboembolism*2 + Vascular_Disease_History ,
    Atria_Bleeding_Score = Anemia * 3 + Severe_Renal_Disease * 3 + Hypertension + Prior_Hemorrahge +case_when(AGE >= 75 ~ 2, .default = 0 ),
    Charlson_Index = Myocardial_Infarction + Congestive_Heart_Failure + Peripheral_Vascular_Disease
    + Previous_Cerebrovascular_Disease + Dementia + Chronic_Pulmonary_Disease 
    + Rheumatic_Disease + Peptic_Ulcer_Disease + Mild_Liver_Disease + Hemiplegia *2 + Renal_Disease + AIDS*6
    + case_when(Cancer == 1 & Metastatic_Solid_Tumor == 0 ~ 2 , Metastatic_Solid_Tumor == 1 ~ 6 , .default = 0 )
    + case_when(Diabetes_With_Chronic_Complications == 1 ~ 2, Diabetes_Without_Chronic_Complications == 1 & Diabetes_With_Chronic_Complications == 0 ~ 1, .default = 0 )
    + case_when(Moderate_Or_Severe_Liver_Disease == 1 ~ 3, Moderate_Or_Severe_Liver_Disease == 0 & Mild_Liver_Disease == 1 ~ 1, .default = 0)
  )



# Adding background info regarding income, hospital type and Race, also redefining gender and mortality columns
current_data = current_data %>%
  mutate(Median_Income_Quartile =
           case_when(ZIPINC_QRTL == 1 ~ "0-25th percentile",
                    ZIPINC_QRTL == 2 ~ "25-50th percentile",
                    ZIPINC_QRTL == 3 ~ "50-75th percentile",
                    ZIPINC_QRTL == 4 ~ "75-100th percentile"),
         White_Ethnicity_Rate = 
           case_when(RACE == 1 ~ "1", .default = "0" ),
         Hospital_Type = 
           case_when(HOSP_LOCTEACH == 3 ~ "Urban, teaching",
                     HOSP_LOCTEACH == 2 ~ "Urban, Non-teaching",
                     HOSP_LOCTEACH == 1 ~ "Rural"))


###Loading Complications info to be searched and adding complications columns:
Complications_DF <- read.csv("Complications.csv")
Categories_DF <- subset(Complications_DF, Complications_DF$Category == "Category")
Complications_Codes_DF <- subset(Complications_DF, Complications_DF$Category != "Category")

#Adding basic complication columns. Please DO NOT RUN if complications data frame is not properly loaded
for (i in 1:nrow(Complications_Codes_DF)){
  Comp_Codes <- str_split_1(Complications_Codes_DF[i,2], ",")
  Header <- str_c("I10_", Complications_Codes_DF[i,3])
  current_data = current_data %>%
    mutate(New_Column = case_when(if_any(starts_with(Header),~.x %in% Comp_Codes ) ~1, .default = 0))
  names(current_data)[names(current_data) == "New_Column"] <- Complications_Codes_DF[i,1]
}

#Adding Columns of categories. Previous section must be completed properly before running this section
for (i in 1:nrow(Categories_DF)){
  Category <- str_split_1(Categories_DF[i,2], ",")
  current_data = current_data %>%
    mutate(New_Column = case_when(if_any(Category,~.x == 1 ) ~1, .default = 0))
  names(current_data)[names(current_data) == "New_Column"] <- Categories_DF[i,1]
}

### Adding complication number column:
compication_codes_names_IDX = match(Complications_Codes_DF[,1], names(current_data))

#Creating a list of all complications to be presented in table2
Complications_List <- Complications_DF[,1]

##Next segment adds the subset column that divides patients into two subgroups, and excludes project-specifically inappropriate patients (in this case, patients with MVP without MR). 
#If you wish to subset differently do not run the next segment. Instead, use the following code, make sure to change file name
# write_sav(current_data, "YOUR_FILE_NAME.sav")
#after running the line above subset as you wish in SPSS, then import the files using the code below, change names as desired
# data_frame_name <- read_sav("YOUR_FILE_NAME.csv")
### Creating a subset column
# on current project subset_column is MR. You can change accordingly
Subset_Values <- c("Q233","I340", "I051") ## Values of mitral regurgitation
Excluded_Values <- c("I341") # Mitral valve prolapse. 
#following segment excludes patients with MVP without an additional diagnosis of MR 
current_data = current_data %>%
  mutate(Subset_Column = case_when(if_any(starts_with("I10_DX"),~.x %in% Subset_Values ) ~1, .default = 0),
         Excluded_Values = case_when(if_any(starts_with("I10_DX"),~.x %in% Excluded_Values ) ~1, .default = 0))
Subset_No_Variant <- subset(current_data, (Subset_Column == 0 & Excluded_Values == 0))
Subset_Variant <- subset(current_data, Subset_Column == 1)
current_data <- rbind(Subset_No_Variant, Subset_Variant)

print(nrow(current_data)) # number of rows after eliminating MVP patients
print(sum(current_data["DISCWT"])) # number of  weighted rows after eliminating MVP patients

# following line locates the index of weights column. Please change accordingly in newer versions of ICD etc.
Weights_Column_Name = "DISCWT"
Weights_Column_IDX <- match(Weights_Column_Name,names(current_data))

#Following function tests normality of contentious variables for using kolmogorov-smirnov normality test and then calculates t test or wilcoxon, accordingly
Continuos_Test <- function( Column_IDX, current_data, current_table, treat_as_normal) {
  n = 5
  No_Condition_Subset_Column <- unlist(current_data[current_data$Subset_Column == 0, Column_IDX])
  No_Condition_Subset_Column <- rep(No_Condition_Subset_Column, n)
  Condition_Subset_Column <- unlist(current_data[current_data$Subset_Column == 1, Column_IDX])
  Condition_Subset_Column <- rep(Condition_Subset_Column, n)
  if (treat_as_normal == 1){
     p_val <- t.test(No_Condition_Subset_Column, Condition_Subset_Column)$p.value
     no_cond_mean <- mean(No_Condition_Subset_Column, na.rm= TRUE)
     cond_mean <-mean(Condition_Subset_Column, na.rm= TRUE)
     sd_no_cond <- sd(No_Condition_Subset_Column, na.rm= TRUE)
     sd_cond <- sd(Condition_Subset_Column, na.rm= TRUE)
     No_Cond_Val <- str_c(toString(round(no_cond_mean, 1)), "+-" ,toString(round(sd_no_cond, 1)))
     Cond_Val <- str_c(toString(round(cond_mean, 1)), "+-" ,toString(round(sd_cond, 1)))}
  else {
    p_val = wilcox.test(No_Condition_Subset_Column, Condition_Subset_Column)$p.value
    cond_median <-median(Condition_Subset_Column, na.rm= TRUE)
    comd_mean <- mean(Condition_Subset_Column, na.rm= TRUE)
    no_cond_median <- median(No_Condition_Subset_Column, na.rm= TRUE)
    no_cond_mean <- mean(No_Condition_Subset_Column, na.rm= TRUE)
    cond_75th <- quantile(Condition_Subset_Column,  0.75) 
    cond_25th <- quantile(Condition_Subset_Column,  0.25) 
    no_cond_75th <- quantile(No_Condition_Subset_Column, 0.75, na.rm = TRUE)
    no_cond_25th <- quantile(No_Condition_Subset_Column, 0.25, na.rm= TRUE)
    No_Cond_Val <- str_c(toString(no_cond_median), " (", toString(no_cond_25th), "-", toString(no_cond_75th), ")")
    Cond_Val <- str_c(toString(cond_median), " (", toString(cond_25th), "-", toString(cond_75th), ")")
    }
  if (p_val < 0.001) { p_val = "<0.001"}
  else p_val = toString(round(p_val ,3))
  current_table[nrow(current_table)+1 ,] = c(str_replace_all(names(current_data)[Column_IDX], "_", " "), No_Cond_Val, Cond_Val, p_val)
  return(current_table)
}

Sum_Weights_No_Var <- sum(current_data[which(current_data$Subset_Column == 0),Weights_Column_IDX])
Sum_Weights_Var <- sum(current_data[which(current_data$Subset_Column == 1),Weights_Column_IDX])

## following function creates a weighted chi_square test, 
#it also returns the weighted frequency of each group and (%),and adjusts if weighted_n<10
Categorical_Test <- function(current_colunm_IDX, current_data,
                                  Sum_Weights_No_Var, Sum_Weights_Var,current_table){
  col_name = str_c(str_replace_all(names(current_data)[current_colunm_IDX], "_", " "), " n,(%)")
  is_group = 0
  print(names(current_data)[current_colunm_IDX])
  print(str_sub(names(current_data)[current_colunm_IDX],start = -5))
  if (str_sub(names(current_data)[current_colunm_IDX],start = -5) == "Group") {is_group = 1}
  frq_tab = current_data %>%
    group_by(current_data[,current_colunm_IDX], Subset_Column) %>%
    summarise(frequency = sum(DISCWT))
  frq_tab <- frq_tab %>%
    pivot_wider(names_from = colnames(.)[2], values_from = frequency)
  freq_cols <- c(2,3)
  frq_tab = frq_tab %>% replace(is.na(.), 0)
  sub_categories <- frq_tab[,1]
  frq_tab <- round(frq_tab[,freq_cols])
  frq_tabl_nrow <- nrow(frq_tab)
  if (frq_tabl_nrow == 1) {return(current_table)}
  excp_tab <- chisq.test(frq_tab)$expected
  if (nrow(excp_tab) > 1) {min_exp_val <- min(min(excp_tab[1,]),min(excp_tab[,2]))}
  else min_exp_val = 0
  if (min_exp_val >= 5 ) {p_val <- chisq.test(frq_tab)$p.value
  print(excp_tab)
  print("Pearsons")}
  else {p_val <- fisher.test(frq_tab)$p.value}
  if (p_val < 0.001) {p_val = "<0.001"}
  else {p_val = round(p_val, 3)
    p_val = format(p_val, scientific = FALSE)
    p_val = toString(p_val)}
  if (frq_tabl_nrow == 2 & is_group == 0){
    if (frq_tab[2,1] >= 10 || frq_tab[2,1] == 0 ) { 
      No_Cond_Val <- str_c(toString(frq_tab[2,1]), " (", 
                           toString(round(100*frq_tab[2,1]/Sum_Weights_No_Var ,2)), ")" )}
    else 
    { No_Cond_Val <- str_c("<10 (<", toString(round(100*10/Sum_Weights_No_Var ,2)), ")" )  }
    if (frq_tab[2,2] == 0 || frq_tab[2,2] >= 10){
      Cond_Val <- str_c(toString(frq_tab[2,2]), "(", toString(round(100*frq_tab[2,2]/Sum_Weights_Var ,2)), ")" )}
    else 
    { Cond_Val <- str_c("<10 (<", toString(round(100*10/Sum_Weights_Var ,2)), ")" ) }
    current_table[nrow(current_table)+1, ] = c(col_name, No_Cond_Val, Cond_Val, p_val)
  }
  else {
    current_table[nrow(current_table)+1, ] = c(col_name, "", "", p_val)
    for (i in 1:frq_tabl_nrow){
      if (frq_tab[i,1] >= 10 || frq_tab[i,1] == 0 ) { 
        No_Cond_Val <- str_c(toString(frq_tab[i,1]), " (", 
                             toString(round(100*frq_tab[i,1]/Sum_Weights_No_Var ,2)), ")" )}
      else 
      { No_Cond_Val <- str_c("<10 (<", toString(round(100*10/Sum_Weights_No_Var ,2)), ")" )  }
      if (frq_tab[i,2] == 0 || frq_tab[i,2] >= 10){
        Cond_Val <- str_c(toString(frq_tab[i,2]), "(", toString(round(100*frq_tab[i,2]/Sum_Weights_Var ,2)), ")" )}
      else 
      { Cond_Val <- str_c("<10 (<", toString(round(100*10/Sum_Weights_Var ,2)), ")" ) }
       current_table[nrow(current_table) +1, ] = c(sub_categories[i,1], No_Cond_Val, Cond_Val, "")
      
    }
  }
  return(current_table)}

#define variables and create table 1
Continous_Columns_DF <- read.csv("Continous_Columns.csv")
No_Cond_Name <- str_c("No ", Subset_Condition_Name, " Patients", " (n=", round(Sum_Weights_No_Var), ")")
Cond_Name <- str_c(Subset_Condition_Name, " Patients", " (n=", round(Sum_Weights_Var), ")")
Table1 = data.frame("Variable", No_Cond_Name, Cond_Name, "P Value")
Table1_Continuos_Varaibles <- Continous_Columns_DF[Continous_Columns_DF[,2] == 1,]$Variable_Name
for (i in 1:length(Table1_Continuos_Varaibles)) {
  column_IDX = match(Table1_Continuos_Varaibles[i], names(current_data))
  is_normal = Continous_Columns_DF[i,3]
  Table1 = Continuos_Test(column_IDX, current_data, Table1, is_normal)}
for (i in 1:length(Table1_Categorical_Variables)) {
  column_IDX = match(Table1_Categorical_Variables[i], names(current_data))
  Table1 = Categorical_Test(column_IDX, current_data, Sum_Weights_No_Var ,Sum_Weights_Var, Table1)}
write.csv(Table1, "table1.csv", row.names = FALSE)



#Define variables and create table 2
Table2 = data.frame("Variable", No_Cond_Name, Cond_Name, "P Value")
Table2_Continuos_Variables <- Continous_Columns_DF[Continous_Columns_DF[,2] == 2,]$Variable_Name
Table2_Categorical_Variables = Complications_DF[,1] #created by the complications csv file
Table2_Categorical_Variables <- append(Table2_Categorical_Variables, c("Mortality")) # adds mortality
for (i in 1:length(Table2_Continuos_Variables)){
  column_IDX = match(Table2_Continuos_Variables[i], names(current_data))
  is_normal = Continous_Columns_DF[i,3]
  Table2 = Continuos_Test(column_IDX, current_data, Table2, is_normal)}
for (i in 1:length(Table2_Categorical_Variables)){
  column_IDX = match( Table2_Categorical_Variables[i], names(current_data))
  Table2 = Categorical_Test(column_IDX, current_data, Sum_Weights_No_Var ,Sum_Weights_Var, Table2)}
write.csv(Table2, "table2.csv", row.names = FALSE)

## Count all complications
100* nrow( current_data%>%
  filter(current_data$Total_Complication_Rate ==1)) / nrow(current_data)

#change categorical background characteristics factor
Categorical_Varaibles_to_Factor <- append(Table1_Categorical_Variables, "Subset_Column")
for (i in 1:length(Categorical_Varaibles_to_Factor )){
  IDX = match(Categorical_Varaibles_to_Factor [i], names(current_data))
  Col_Content <- unlist(current_data[, IDX])
  current_data= current_data %>%
    mutate(New_Column = as.factor(Col_Content))
  New_Name <- str_c("Factor_" ,Categorical_Varaibles_to_Factor [i])
  names(current_data)[names(current_data) == "New_Column"] <- New_Name}


# Following function checks for significance of relation between each of the background characteristics and a chosen complication, and then selects the significant characteristics.
#Selected characteristics are tested in a logistics regression model. Function returns a table showing each characteristic's OR, 95% CI and P value as well as the model's R squared and its p value.
# rows are duplicated *5 as every row is the equivalent of 5 patients in reality.
Log_Model <- function(complication, current_data, Table1_Continuos_Varaibles, Table1_Categorical_Variables, logistic_regression_table) {
  formula_syntax = paste(complication, "~ Factor_Subset_Column")
  Complication_Col_IDX = match(complication, names(current_data))
  for (i in 1:length(Table1_Continuos_Varaibles))
  { Col_IDX = match(Table1_Continuos_Varaibles[i], names(current_data))
    No_Condition_Subset_Column <- unlist(current_data[current_data[,Complication_Col_IDX]== 0, Col_IDX])
    No_Condition_Subset_Column <- rep(No_Condition_Subset_Column, 5) 
    Condition_Subset_Column <- unlist(current_data[current_data[,Complication_Col_IDX] == 1, Col_IDX])
    Condition_Subset_Column <- rep(Condition_Subset_Column, 5)
    if (Continous_Columns_DF[i,3] ==1){
      p_val = t.test(No_Condition_Subset_Column, Condition_Subset_Column)$p.value
      if (p_val <= 0.05){
        formula_syntax = paste(formula_syntax, " +", Table1_Continuos_Varaibles[i])}
      }
    else
    {p_val = wilcox.test(No_Condition_Subset_Column, Condition_Subset_Column)$p.value
      if (p_val <= 0.05){
        formula_syntax = paste(formula_syntax, " +", Table1_Continuos_Varaibles[i])}}
  }
  for (i in 1:length(Table1_Categorical_Variables))
  { factor_col_name = str_c("Factor_",Table1_Categorical_Variables[i] )
    current_column_IDX = match(factor_col_name, names(current_data))
    frq_tab = current_data %>%
    group_by(current_data[,current_column_IDX], current_data[,Complication_Col_IDX]) %>%
    summarise(frequency = sum(DISCWT))
    unique_vals <- unique(current_data[, current_column_IDX])
    if (2*nrow(unique_vals) != nrow(frq_tab) ) {next}
    frq_tab <- frq_tab %>%
    pivot_wider(names_from = colnames(.)[2], values_from = frequency)
      freq_cols <- c(2,3)
    frq_tab = frq_tab %>% replace(is.na(.), 0)
    sub_categories <- frq_tab[,1]
    frq_tab <- round(frq_tab[,freq_cols])
    p_val <- chisq.test(frq_tab)$p.value
    if (p_val<= 0.05) {
      formula_syntax = paste(formula_syntax, " +" , factor_col_name)
    }
  }
  print(formula_syntax)
  logistic_regression_model <-glm(formula_syntax, data = current_data, 
                                  family = binomial(link= "logit") , control = glm.control(maxit = 1000))
  
  ll_null <- logistic_regression_model$null.deviance/-2
  ll_proposed <- logistic_regression_model$deviance/-2
  R_square_p_val <- 1- pchisq(2*(ll_proposed - ll_null), df = (length(logistic_regression_model$coefficients)-1))
  McFaddens_Pseudo_R = (ll_null-ll_proposed)/ll_null
  coeff <- summary(logistic_regression_model)$coefficients
  lower_CI <- round(exp(coeff [,1] - 1.96* coeff[,2]),2)
  upper_CI <- round(exp(coeff [,1] + 1.96* coeff[,2]),2)
  print(coef)
  probabilities <- logistic_regression_model %>% predict(current_data, type = "response")
  predicted.classes <- ifelse(probabilities > 0.5, 1, 0)
  accuracy_level <- mean(predicted.classes == current_data[,Complication_Col_IDX])
  for (i in 2:length(logistic_regression_model$coefficients)){
    odds_ratio_95_ci <- str_c(round(exp(coeff[i,1]),2), " [",  lower_CI[i], "-",  upper_CI[i], "]")  
    logistic_regression_table[nrow(logistic_regression_table)+1, ] = c(complication ,rownames(coeff)[i],
                                                                       round(exp(coeff[i,1]),2), lower_CI[i], upper_CI[i], 
                                                                       odds_ratio_95_ci, coeff[i,4],
                                                                       McFaddens_Pseudo_R, R_square_p_val, accuracy_level)
    }
  return(logistic_regression_table)
  }

# Choose all statistically Significant Variables
# create the logistic regression table
logistic_regression_table <- data.frame("Complication","Background_Charateristic",
                                        "Odds_Ratio", "Lower_Limit", "Upper_Limit", 
                                        "Odds_Ratio_95_CI","P_Value_of_Characteristic",
                                        "R_Square", "P_value_of_R_Square", "Accuracy_Level")
colnames(logistic_regression_table) <- c("Complication","Background_Charateristic",
                               "Odds_Ratio", "Lower_Limit", "Upper_Limit", 
                               "Odds_Ratio_95_CI","P_Value_of_Characteristic",
                               "R_Square", "P_value_of_R_Square", "Accuracy_Level")
logistic_regression_table <- logistic_regression_table[-1,]

# creating a list of all complications that are  significantly differently distributed complication
statistically_significant_complications <- Table2[Table2[,4] <= 0.05, 1]
statistically_significant_complications <- grep("n,", statistically_significant_complications, value=TRUE)
statistically_significant_complications <- str_sub(statistically_significant_complications, 1, -7)
statistically_significant_complications <- str_replace_all(statistically_significant_complications, " ", "_")

#for each complication run the GLM function and ret odds ratio, 95 CI, p value etc. 

for (i in 1:length(statistically_significant_complications)){
  if (statistically_significant_complications[i] %in% Category) {next}
  IDX = match(statistically_significant_complications[i], names(current_data))
  Col_Content <- unlist(current_data[, IDX])
  current_data= current_data %>%
    mutate(New_Column = as.factor(Col_Content))
  New_Name <- str_c("Factor_" ,statistically_significant_complications[i])
  names(current_data)[names(current_data) == "New_Column"] <- New_Name
  logistic_regression_table <- Log_Model(New_Name, current_data, Table1_Continuos_Varaibles, Table1_Categorical_Variables, logistic_regression_table) 
}
# Replace name "subset column" with subset category name
logistic_regression_table [logistic_regression_table$Background_Charateristic == "Factor_Subset_Column1",2 ] = Subset_Condition_Name
logistic_regression_table [ ,1] <- str_replace_all(logistic_regression_table[,1], "Factor_", "")
logistic_regression_table [ ,2] <- str_replace_all(logistic_regression_table[,2], "Factor_", "")
logistic_regression_table [ ,2] <- str_replace_all(logistic_regression_table[,2], "1", "")
logistic_regression_table [,3] <- as.numeric(logistic_regression_table [,3])
logistic_regression_table [,4] <- as.numeric(logistic_regression_table [,4])
logistic_regression_table [,5] <- as.numeric(logistic_regression_table [,5])

logistic_regression_table

write.csv(logistic_regression_table, "Logistic_Regerssion_Results.csv", row.names = FALSE)

#Sub-select MR rows
Subset_Odds_Ratio <- logistic_regression_table[logistic_regression_table[,2]== Subset_Condition_Name,]
Subset_Odds_Ratio[,1] <- str_replace_all(Subset_Odds_Ratio[,1], "_", " ")

# Plot MR rows in graph
jpeg(filename = "Odds_Ratio_Graph.jpg", width=800, height =500, quality = 100)
ggplot(Subset_Odds_Ratio,
  aes(Odds_Ratio, 1:nrow(Subset_Odds_Ratio)))+
  geom_point(colour = "black", size =3) +
  geom_errorbar(aes(xmin=Lower_Limit,
                    xmax=Upper_Limit),
                width= 0.1,
                linewidth =0.7,
                position=position_dodge(.5)) +
  scale_x_continuous(trans = "log10")+
  ggtitle("Adjusted Odds Ratio")+
  theme_bw()+
  scale_y_continuous( name = "In-Hospital Complication",
    breaks = c(1:nrow(Subset_Odds_Ratio)),
                     labels= Subset_Odds_Ratio$Complication,
                   sec.axis = sec_axis(trans =~., name ="Odds Ratio [95% CI]", 
                                       breaks = 1:nrow(Subset_Odds_Ratio),
                                       labels = Subset_Odds_Ratio$Odds_Ratio_95_CI))+
  theme(plot.title = element_text(hjust = 0.5)) + xlab ("Odds Ratio (log10-scale)")

## export graph
dev.off()
