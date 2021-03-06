% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/calculateMortality.r
\name{getMortalityData}
\alias{getMortalityData}
\title{get mortality rate}
\usage{
getMortalityData(connectionDetails, cdmDatabaseSchema,
  cohortDatabaseSchema, outcomeDatabaseSchema, cohortTable, targetCohortId,
  outcomeId = 99, minDateUnit = "year")
}
\arguments{
\item{cdmDatabaseSchema}{}

\item{outcomeId}{for mortality rate, death_id = 99}

\item{minDateUnit}{minumal unit for cohort start date ('year' > 'quarter' > 'month' > 'day')}
}
\description{
get mortality rate
}
