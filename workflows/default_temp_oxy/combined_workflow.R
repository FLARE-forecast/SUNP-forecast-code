library(tidyverse)
library(lubridate)
lake_directory <- here::here()
print(lake_directory)
setwd(lake_directory)
forecast_site <- "sunp"
configure_run_file <- "configure_run.yml"
update_run_config <- TRUE
config_set_name <- "default_temp_oxy"

Sys.setenv("AWS_DEFAULT_REGION" = "amnh1",
           "AWS_S3_ENDPOINT" = "osn.mghpcc.org",
           "USE_HTTPS" = TRUE)

#' Source the R files in the repository
source(file.path(lake_directory, "R", "insitu_qaqc_withDO.R"))

#' Generate the `config_obs` object and create directories if necessary

config_obs <- FLAREr::initialize_obs_processing(lake_directory, config_set_name = config_set_name, observation_yml = "observation_processing.yml")
config <- FLAREr::set_configuration(configure_run_file,lake_directory, config_set_name = config_set_name)

#' Clone or pull from data repositories

FLAREr::get_git_repo(lake_directory,
                     directory = config_obs$realtime_insitu_location,
                     git_repo = "https://github.com/FLARE-forecast/SUNP-data.git")

#' Download files from EDI and Zenodo
#'

dir.create(file.path(config_obs$file_path$data_directory, "hist-data"),showWarnings = FALSE)

# high frequency buoy data
FLAREr::get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/f4d3535cebd96715c872a7d3ca45c196",
                     file = file.path("hist-data", "hist_buoy_do.csv"),
                     lake_directory)

FLAREr::get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/1f903796efc8d79e263a549f8b5aa8a6",
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
cleaned_insitu_file <- insitu_qaqc_withDO(realtime_file = file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[1]),
                                   hist_buoy_file = c(file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[2]), file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[5])),
                                   hist_manual_file = file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[3]),
                                   hist_all_file =  file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[4]),
                                   maintenance_url = "https://docs.google.com/spreadsheets/d/1IfVUlxOjG85S55vhmrorzF5FQfpmCN2MROA_ttEEiws/edit?usp=sharing",
                                   variables = c("temperature", "oxygen"),
                                   cleaned_insitu_file = file.path(config_obs$file_path$targets_directory, config_obs$site_id, paste0(config_obs$site_id,"-targets-insitu.csv")),
                                   config = config_obs,
                                   lake_directory = lake_directory)

#' Move targets to s3 bucket

message("Successfully generated targets")

FLAREr::put_targets(site_id = config_obs$site_id,
                    cleaned_insitu_file,
                    use_s3 = config$run_config$use_s3,
                    config = config)

message("Successfully moved targets to s3 bucket")


noaa_ready <- TRUE

while(noaa_ready){

  config <- FLAREr::set_configuration(configure_run_file,lake_directory, config_set_name = config_set_name)

  print(config)

  output <- FLAREr::run_flare(lake_directory = lake_directory,
                              configure_run_file = configure_run_file,
                              config_set_name = config_set_name)


  forecast_start_datetime <- lubridate::as_datetime(config$run_config$forecast_start_datetime) + lubridate::days(1)
  start_datetime <- lubridate::as_datetime(config$run_config$forecast_start_datetime)
  restart_file <- paste0(config$location$site_id,"-", (lubridate::as_date(forecast_start_datetime)- days(1)), "-",config$run_config$sim_name ,".nc")

  FLAREr::update_run_config2(lake_directory = lake_directory,
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
                             bucket = config$s3$warm_start$bucket,
                             endpoint = config$s3$warm_start$endpoint,
                             use_https = TRUE)

  #RCurl::url.exists(ping_url, timeout = 5)

  noaa_ready <- FLAREr::check_noaa_present_arrow(lake_directory = lake_directory,
                                                 configure_run_file = configure_run_file,
                                                 config_set_name = config_set_name)
}
