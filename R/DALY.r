# Copyright 2019 Observational Health Data Sciences and Informatics
#
# This file is part of Argos
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Calculate Years of Life Lost (YLL), Years Lost due to Disability (YDD), and Disability-Adjusted Life Year (DALY)
#' @param outcomeData                  outcomeData generated by Argos package.
#' @param refLifeExpectancy        reference  life expectancy data to calculate YDD. The default life expectancy table is provided and can be loaded via loadLifeExpectancy function
#' @param disabilityWeight         disability weight for the certain condition of plpData to calculate YLD. if this is 0, YLD is 0. It should be float value (0~1).
#' @param outcomeDisabilityWeight   Disability weight for outcome.  If the outcome is death, then disability weight should be 1. It should be float value (0~1).
#' @param minTimeAtRisk            time at risk (days). usually it should be identical to the minTAR of plpData
#' @param discount                 discount value, float(0~1). default value is 0.3.
#' @param ageWeghting               logical value (TRUE or FALSE). 
#' @param outputFolder             outputFolder
#' 
#' @export
calculateDALY <- function (outcomeData,
                           refLifeExpectancy,
                           disabilityWeight=0.5,
                           outcomeDisabilityWeight = 1,
                           minTimeAtRisk,
                           discount = 0.3,
                           ageWeighting =TRUE,
                           outputFolder){
    
    #load covariates
    #limit covariates of plpData to the population
    covariates<-ff::as.ram(limitCovariatesToPopulation(covariates = outcomeData$plpData$covariates,rowIds = ff::as.ff(outcomeData$population$rowId)))
    #load covariate reference
    covRef<-ff::as.ram(outcomeData$plpData$covariateRef)
    #limit covarite Ref to the existing covarites in the population
    covRef <- covRef [covRef$covariateId %in% unique(covariates$covariateId), ]
    cohort<-outcomeData$population
    
    #extract only age/gender covariate from covariates
    ageCov<-covariates[covariates$covariateId==covRef[covRef$covariateName=="age in years","covariateId"],c("rowId","covariateValue")]#covariateId 1002
    maleCov <-covariates[covariates$covariateId==covRef[covRef$covariateName=="gender = MALE","covariateId"],c("rowId","covariateValue")]#covariateId 8507001 #8507
    femaleCov <-covariates[covariates$covariateId==covRef[covRef$covariateName=="gender = FEMALE","covariateId"],c("rowId","covariateValue")]#covariateId 8532001 #8532
    #replace covariate value with gender concept id
    maleCov$covariateValue = maleCov$covariateValue*8507
    femaleCov$covariateValue = femaleCov$covariateValue*8532
    #row bind of maleCov and femaleCov to make gender Covariates
    genderCov<-rbind(maleCov,femaleCov)
    
    #replace column names from covariate value to age/genderValue
    colnames(ageCov)<-gsub("covariateValue","age",colnames(ageCov))
    colnames(genderCov)<-gsub("covariateValue","gender",colnames(genderCov))
    
    #merge ageCov and genderCov with cohort, which 
    cohort <- cohort %>%
        dplyr::left_join(ageCov, by="rowId") %>%
        dplyr::left_join(genderCov, by="rowId")
    
    #make a age, age at outcome, and then life expectancy at the age of outcome
    cohort<-cohort %>% 
        dplyr::mutate(startYear = lubridate::year(cohortStartDate)) %>%
        dplyr::mutate(ageAtOutcome = age + round(daysToEvent/365,0)) %>%
        dplyr::mutate(yeartAtOutcome = startYear + round(daysToEvent/365,0))
    
    #cohort only with outcome
    cohortWithOutcome<-cohort[cohort$outcomeCount>=1,]
    #load reference life expectancy
    refLifeExpectancy= loadLifeExpectancy('KOR')
    
    #add life expectance to the cohort
    cohortWithOutcome <- cohortWithOutcome %>%
        dplyr::inner_join(refLifeExpectancy, by = c("ageAtOutcome"="startAge", "gender"="genderConceptId","yeartAtOutcome"= "startYear"))
    
    
    #calculate YLL (Years of Life Lost)
    yll<-apply(cohortWithOutcome,MARGIN = 1,FUN = function(x){
        burden(disabilityWeight= 1.00, 
               disabilityStartAge=as.numeric(x[["ageAtOutcome"]]), 
               duration= as.numeric(x[["expectedLifeRemained"]]),
               ageWeighting=ageWeighting, 
               discount=discount, 
               age=as.numeric(x[["age"]]))
    })
    
    #calculate YLD (Years Lost due to Disability)
    yld<-apply(cohort,MARGIN = 1,FUN = function(x){
        burden(disabilityWeight= disabilityWeight, 
               disabilityStartAge=as.numeric(x[["age"]]), 
               duration= as.numeric(x[["survivalTime"]])/365,
               ageWeighting=ageWeighting, 
               discount=discount, 
               age=as.numeric(x[["age"]]))
    })
    
    result = data.frame(yllSum = sum(yll,na.rm =TRUE),
                        yldSum = sum(yld,na.rm =TRUE),
                        dalySum = sum(yll,na.rm =TRUE) + sum(yld,na.rm =TRUE),
                        yllPerEvent = sum(yll, na.rm = TRUE)/nrow(cohort),
                        yldPerEvent = sum(yld, na.rm = TRUE)/nrow(cohort),
                        dalyPerEvent = sum(yll,yld,na.rm =TRUE)/nrow(cohort)
                        )
    
    return (result)
}

##Helper function for calculating integral in DALY function
f<-function(x,ageWeighting,C = 0.1658, beta = 0.04, discount, age){
    ageWeighting * C *x *exp(-beta*x)*exp(-discount*(x-age))+ (1-ageWeighting)*exp(-discount*(x-age))
}

#'Burden calculation function
#'@param disabilityWeight
#'@param disabilityStartAge
#'@param duration
#'@param ageWeighting
#'@param discount
#'@param age
#'@export
burden <- function(disabilityWeight,
                   disabilityStartAge,
                   duration,
                   ageWeighting,
                   discount,
                   age){
    burdenValue=disabilityWeight * integrate(f, lower = disabilityStartAge, upper = disabilityStartAge+duration, ageWeighting=ageWeighting, discount=discount, age=age )$value
    return(burdenValue)
}

