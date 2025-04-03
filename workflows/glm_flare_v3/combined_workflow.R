library(tidyverse)
library(lubridate)

#remotes::install_github('flare-forecast/FLAREr@single-parameter')
remotes::install_github('flare-forecast/FLAREr')
remotes::install_github("rqthomas/GLM3r")
Sys.setenv('GLM_PATH'='GLM3r')

remotes::install_github("gagolews/stringi")
library(stringi)

print('Done with package/credential set up')

lake_directory <- here::here()
setwd(lake_directory)
forecast_site <- 'sunp'
configure_run_file <- "configure_run.yml"
config_set_name <- "glm_flare_v3"

Sys.setenv("AWS_DEFAULT_REGION" = "renc",
           "AWS_S3_ENDPOINT" = "osn.xsede.org",
           "USE_HTTPS" = TRUE)

#' Source the R files in the repository
source(file.path(lake_directory, "R", "insitu_qaqc_withDO.R"))
source(file.path(lake_directory, "R", "get_edi_file.R"))
source(file.path(lake_directory, "R", "generate_forecast_score_arrow.R"))

print('done with sourcing')

#' Generate the `config_obs` object and create directories if necessary

config_obs <- yaml::read_yaml(file.path(lake_directory,'configuration',config_set_name,'observation_processing.yml'))
print('done with configuration 1')
configure_run_file <- "configure_run.yml"
print('done with configuration 2')
config <- FLAREr:::set_up_simulation(configure_run_file,lake_directory, config_set_name = config_set_name)
print('done with configuration 3')
#' Clone or pull from data repositories

FLAREr:::get_git_repo(lake_directory,
                     directory = config_obs$realtime_insitu_location,
                     git_repo = "https://github.com/FLARE-forecast/SUNP-data.git")

#' Download files from EDI and Zenodo
#'

#dir.create(file.path(config_obs$file_path$data_directory, "hist-data"),showWarnings = FALSE)
dir.create(file.path(lake_directory, "targets", config_obs$site_id), showWarnings = FALSE)

# high frequency buoy data
get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/f4d3535cebd96715c872a7d3ca45c196",
                     file = file.path("hist-data", "hist_buoy_do.csv"),
                     lake_directory)

get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/1f903796efc8d79e263a549f8b5aa8a6",
                     file = file.path("hist-data", "hist_buoy_temp.csv"),
                     lake_directory)

# manually collected data
if(!file.exists(file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2023.1.zip'))){
  download.file(url = 'https://zenodo.org/records/8003784/files/Lake-Sunapee-Protective-Association/LMP-v2023.2.zip?download=1',
                destfile = file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2023.2.zip'),
                mode = 'wb')
  unzip(file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2023.2.zip'),
        files = file.path('Lake-Sunapee-Protective-Association-LMP-42d9cc5', 'primary files', 'LSPALMP_1986-2022_v2023-06-04.csv'),
        exdir = file.path(lake_directory, 'data_raw', 'hist-data', 'LSPA_LMP'),
        junkpaths = TRUE)
}


#' Clean up insitu

# QAQC insitu buoy data
cleaned_insitu_file <- insitu_qaqc_withDO(realtime_file = file.path('data_raw',config_obs$insitu_obs_fname[1]),
                                   hist_buoy_file = c(file.path('data_raw',config_obs$insitu_obs_fname[2]), file.path('data_raw',config_obs$insitu_obs_fname[5])),
                                   hist_manual_file = file.path('data_raw',config_obs$insitu_obs_fname[3]),
                                   hist_all_file =  file.path('data_raw',config_obs$insitu_obs_fname[4]),
                                   maintenance_url = "https://docs.google.com/spreadsheets/d/1IfVUlxOjG85S55vhmrorzF5FQfpmCN2MROA_ttEEiws/edit?usp=sharing",
                                   variables = c("temperature", "oxygen"),
                                   cleaned_insitu_file = file.path('targets', config_obs$site_id, paste0(config_obs$site_id,"-targets-insitu.csv")),
                                   config = config_obs,
                                   lake_directory = lake_directory)

#' Move targets to s3 bucket

message("Successfully generated targets")

FLAREr:::put_targets(site_id = config_obs$site_id,
                    cleaned_insitu_file,
                    use_s3 = config$run_config$use_s3,
                    config = config)

message("Successfully moved targets to s3 bucket")


noaa_ready <- TRUE

while(noaa_ready){

  config <- FLAREr:::set_up_simulation(configure_run_file,lake_directory, config_set_name = config_set_name)

  output <- FLAREr::run_flare(lake_directory = lake_directory,
                              configure_run_file = configure_run_file,
                              config_set_name = config_set_name)


  message("Scoring forecasts")
  forecast_s3 <- arrow::s3_bucket(bucket = config$s3$forecasts_parquet$bucket, endpoint_override = config$s3$forecasts_parquet$endpoint, anonymous = TRUE)
  forecast_df <- arrow::open_dataset(forecast_s3) |>
    dplyr::mutate(reference_date = lubridate::as_date(reference_date)) |>
    dplyr::filter(model_id == 'glm_flare_v3',
                  site_id == forecast_site,
                  reference_date == lubridate::as_datetime(config$run_config$forecast_start_datetime)) |>
    dplyr::collect()

  print(paste0('LENGTH OF FORECAST OUTPUT: ', nrow(forecast_df)))

  if(config$output_settings$evaluate_past & config$run_config$use_s3){
    #past_days <- lubridate::as_date(forecast_df$reference_datetime[1]) - lubridate::days(config$run_config$forecast_horizon)
    past_days <- lubridate::as_date(lubridate::as_date(config$run_config$forecast_start_datetime) - lubridate::days(config$run_config$forecast_horizon))

    #vars <- arrow_env_vars()
    past_s3 <- arrow::s3_bucket(bucket = config$s3$forecasts_parquet$bucket, endpoint_override = config$s3$forecasts_parquet$endpoint, anonymous = TRUE)
    past_forecasts <- arrow::open_dataset(past_s3) |>
      dplyr::mutate(reference_date = lubridate::as_date(reference_date)) |>
      dplyr::filter(model_id == 'glm_flare_v3',
                    site_id == forecast_site,
                    reference_date == past_days) |>
      dplyr::collect()
    #unset_arrow_vars(vars)
  }else{
    past_forecasts <- NULL
  }

  combined_forecasts <- dplyr::bind_rows(forecast_df, past_forecasts)

  combined_forecasts$site_id <- forecast_site
  combined_forecasts$model_id <- config$run_config$sim_name

  targets_df <- read_csv(file.path(config$file_path$qaqc_data_directory,paste0(config$location$site_id, "-targets-insitu.csv")),show_col_types = FALSE)


  scoring <- generate_forecast_score_arrow(targets_df = targets_df,
                                           forecast_df = combined_forecasts, ## only works if dataframe returned from output
                                           use_s3 = config$run_config$use_s3,
                                           bucket = config$s3$scores$bucket,
                                           endpoint = config$s3$scores$endpoint,
                                           local_directory = './scores/sunp',
                                           variable_types = c("state","parameter"))



  forecast_start_datetime <- lubridate::as_datetime(config$run_config$forecast_start_datetime) + lubridate::days(1)
  start_datetime <- lubridate::as_datetime(config$run_config$forecast_start_datetime)
  restart_file <- paste0(config$location$site_id,"-", (lubridate::as_date(forecast_start_datetime)- days(1)), "-",config$run_config$sim_name ,".nc")

  FLAREr:::update_run_config(lake_directory = lake_directory,
                             configure_run_file = configure_run_file,
                             restart_file = restart_file,
                             start_datetime = start_datetime,
                             end_datetime = NA,
                             forecast_start_datetime = forecast_start_datetime,
                             forecast_horizon = config$run_config$forecast_horizon,
                             sim_name = config$run_config$sim_name,
                             site_id = config$location$site_id,
                             configure_flare = config$run_config$configure_flare,
                             configure_obs = config$run_config$configure_obs,
                             use_s3 = config$run_config$use_s3,
                             bucket = config$s3$restart$bucket,
                             endpoint = config$s3$restart$endpoint,
                             use_https = TRUE)

  #RCurl::url.exists(ping_url, timeout = 5)

  noaa_ready <- FLAREr::check_noaa_present(lake_directory,
                                                  configure_run_file,
                                                  config_set_name = config_set_name)
}
