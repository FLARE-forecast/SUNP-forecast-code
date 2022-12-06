#print(Sys.getenv())

#remotes::install_github("rqthomas/FLAREr")
#install.packages('gsheet')
library(tidyverse)
library(lubridate)

lake_directory <- here::here()
forecast_site <- "sunp"
configure_run_file <- "configure_run.yml"
config_files <- "configure_flare.yml"
config_set_name <- "UC_analysis"
use_archive <- FALSE

if(use_archive){
  use_s3 <- FALSE
}else{
  Sys.setenv('AWS_DEFAULT_REGION' = 's3',
             'AWS_S3_ENDPOINT' = 'flare-forecast.org',
             'USE_HTTPS' = TRUE)
  use_s3 <- FALSE
}

# set up date vectors for each year
days_22 <- seq.Date(as.Date('2022-04-27'), as.Date('2022-10-17'), by = 1) ## do again for 2021, 2020, 2019 and make list of the years
num_forecasts <- c(length(days_22)) # addin 2021, 2020, 2019
days_between_forecasts <- 1
forecast_horizon <- 35
starting_date <- as.Date(days_22[1]) # addin 2021, 2020, 2019
second_date <- starting_date + lubridate::days(5)  #months(1) + lubridate::days(5) # set up the spinup period

start_dates <- lubridate::as_date(rep(NA, num_forecasts + 1))
end_dates <- lubridate::as_date(rep(NA, num_forecasts + 1))
start_dates[1] <- starting_date
end_dates[1] <- second_date

for(i in 2:(num_forecasts+1)){
  start_dates[i] <- lubridate::as_date(end_dates[i-1])
  end_dates[i] <- start_dates[i] + lubridate::days(days_between_forecasts)
}

# limit to the last day when obs occur
start_dates <- start_dates[start_dates <= as.Date(max(days_22))]
end_dates <- end_dates[end_dates <= as.Date(max(days_22))]

# UC analysis vectors
UC_names <- c('parameter', 'initial_condition', 'process', 'weather', 'observation', "all_UC")

# create dataframe with both
sims <- expand.grid(paste0(start_dates,"_",end_dates,"_", forecast_horizon), UC_names)

names(sims) <- c("date","UC_type")

sims$start_dates <- stringr::str_split_fixed(sims$date, "_", 3)[,1]
sims$end_dates <- stringr::str_split_fixed(sims$date, "_", 3)[,2]
sims$horizon <- stringr::str_split_fixed(sims$date, "_", 3)[,3]

sims <- sims |>
  dplyr::mutate(UC_type = as.character(UC_type)) |>
  dplyr::select(-date) |>
  dplyr::distinct_all() |>
  dplyr::arrange(start_dates)

sims$horizon[1:length(UC_names)] <- 0
sims

message("Generating targets")

source(file.path(lake_directory, "R", "insitu_qaqc_withDO.R"))

#' Generate the `config_obs` object and create directories if necessary
message('read config')
config_obs <- FLAREr::initialize_obs_processing(lake_directory, observation_yml = "observation_processing.yml", config_set_name = config_set_name)
dir.create(file.path(lake_directory, "targets", config_obs$site_id), showWarnings = FALSE)

#' Clone or pull from data repositories
message('download git')
FLAREr::get_git_repo(lake_directory,
                     directory = config_obs$realtime_insitu_location,
                     git_repo = "https://github.com/FLARE-forecast/SUNP-data.git")

#' Download files from EDI and Zenodo
dir.create(file.path(config_obs$file_path$data_directory, "hist-data"),showWarnings = FALSE)

# high frequency buoy data
message('download edi')
FLAREr::get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/f4d3535cebd96715c872a7d3ca45c196",
                     file = file.path("hist-data", "hist_buoy_do.csv"),
                     lake_directory)

FLAREr::get_edi_file(edi_https = "https://pasta.lternet.edu/package/data/eml/edi/499/2/1f903796efc8d79e263a549f8b5aa8a6",
                     file = file.path("hist-data", "hist_buoy_temp.csv"),
                     lake_directory)

# manually collected data
if(!file.exists(file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2020.1.zip'))){
  download.file(url = 'https://zenodo.org/record/4652076/files/Lake-Sunapee-Protective-Association/LMP-v2020.1.zip?download=1',
                destfile = file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2020.1.zip'),
                mode = 'wb')
  unzip(file.path(lake_directory, 'data_raw', 'hist-data', 'LMP-v2020.1.zip'),
        files = file.path('Lake-Sunapee-Protective-Association-LMP-271fcb0', 'master files', 'LSPALMP_1986-2020_v2021-03-29.csv'),
        exdir = file.path(lake_directory, 'data_raw', 'hist-data', 'LSPA_LMP'),
        junkpaths = TRUE)
}

# QAQC insitu buoy data
message('run insitu qaqc')
cleaned_insitu_file <- insitu_qaqc(realtime_file = file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[1]),
                                   hist_buoy_file = c(file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[2]), file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[5])),
                                   hist_manual_file = file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[3]),
                                   hist_all_file =  file.path(config_obs$file_path$data_directory, config_obs$insitu_obs_fname[4]),
                                   maintenance_url = "https://docs.google.com/spreadsheets/d/1IfVUlxOjG85S55vhmrorzF5FQfpmCN2MROA_ttEEiws/edit?usp=sharing",
                                   variables = c("temperature", "oxygen"),
                                   cleaned_insitu_file = file.path(config_obs$file_path$targets_directory, config_obs$site_id, paste0(config_obs$site_id,"-targets-insitu.csv")),
                                   config = config_obs,
                                   lake_directory = lake_directory)


message("Successfully generated targets")


# create directories with the UC sim name


for(i in 1:length(UC_names)){
  dir.create(file.path(lake_directory, 'restart', forecast_site, UC_names[i]))
  dir.create(file.path(lake_directory,"forecasts", forecast_site, UC_names[i]))
  dir.create(file.path(lake_directory, "scores", forecast_site, UC_names[i]))
  dir.create(file.path(lake_directory, "flare_tempdir", forecast_site, UC_names[i]))
  
}

starting_index <- 1
# index 415 failed, only 16-day forecasts for some ensembles on 2022-08-09
# no NOAA forecasts on 2022-08-10
# need to fix restart file issue for these days

for(i in starting_index:nrow(sims)){
  
  message(paste0("     index: ", i, " of ", nrow(sims)))
  message(paste0("     Running mode: ", sims$UC_type[i], ", start date: ", sims$start_dates[i]))
  
  UC_mode <- sims$UC_type[i]
  sim_names <- UC_mode

  config <- FLAREr::set_configuration(configure_run_file,lake_directory, config_set_name = config_set_name)

  cycle <- "00"
  
  for(j in 1:length(sim_names)){
    if(file.exists(file.path(lake_directory, "restart", forecast_site, sim_names[j], configure_run_file))){
      unlink(file.path(lake_directory, "restart", forecast_site, sim_names[j], configure_run_file))
      if(use_s3){
        FLAREr::delete_restart(site_id = forecast_site,
                               sim_name = sim_names[j],
                               bucket = config$s3$warm_start$bucket,
                               endpoint = config$s3$warm_start$endpoint)
      }
    }
  }
  
  run_config <- yaml::read_yaml(file.path(lake_directory, "configuration", config_set_name, configure_run_file))
  run_config$configure_flare <- config_files
  run_config$sim_name <- sim_names
  yaml::write_yaml(run_config, file = file.path(lake_directory, "restart", forecast_site, sim_names, configure_run_file))
  config <- FLAREr::set_configuration(configure_run_file,lake_directory, config_set_name = config_set_name)
  config$run_config$start_datetime <- as.character(paste0(sims$start_dates[i], " 00:00:00"))
  config$run_config$forecast_start_datetime <- as.character(paste0(sims$end_dates[i], " 00:00:00"))
  config$run_config$forecast_horizon <- sims$horizon[i]
  
  #set output directory so each frequency/experiment is saved in a separate folder
  config$file_path$forecast_output_directory <- file.path(lake_directory,"forecasts", forecast_site, sims$UC_type[i])
  
  if(i <= length(UC_names)){
    config$run_config$restart_file <- NA
  }else{
    config$run_config$restart_file <- file.path(config$file_path$forecast_output_directory, paste0(config$location$site_id, "-", lubridate::as_date(config$run_config$start_datetime), "-", sim_names, ".nc"))
    if(!file.exists(config$run_config$restart_file )){
      warning(paste0("restart file: ", config$run_config$restart_file, " doesn't exist, switch to most recent restart file"))
      #files <- list.files(path = file.path(config$file_path$forecast_output_directory), pattern = "*.nc")
      #config$run_config$restart_file <- file.path(config$file_path$forecast_output_directory, tail(files, n = 1))
      #config$run_config$start_datetime <- lubridate::ymd(basename(tail(files, n = 1)))
        
    }
    
  }
  
  #config <- FLAREr::set_configuration(configure_run_file,lake_directory, config_set_name = config_set_name, sim_name = sim_names)
  config$model_settings$model <- UC_mode
  config$run_config$sim_name <- sim_names

  run_config <- config$run_config
  yaml::write_yaml(run_config, file = file.path(lake_directory, "restart", forecast_site, sim_names, configure_run_file))
  
  # set UC mode within config file
  # the WRONG WAY
  #id_uc <- which(names(config$uncertainty) == sims$UC_type[i]) 
  #config$uncertainty[id_uc] <- FALSE 
  if(sims$horizon[i] > 1){
    id_uc <- which(names(config$uncertainty) != sims$UC_type[i])

    if(sims$UC_type[i] != 'all_UC'){
      for(t in 1:length(id_uc)){
        config$uncertainty[id_uc[t]] <- FALSE 
      }
    }
  }
  
  # but not met_downscale UC ?
  #config$uncertainty$met_downscale <- TRUE
  
  print(config$uncertainty)
  print(sims$UC_type[i])
  
  config$file_path$execute_directory <- file.path(lake_directory, "flare_tempdir", forecast_site, sim_names)
  config$file_path$restart_directory <- file.path(lake_directory, "restart", forecast_site, sim_names)

  # process met observations
  noaa_forecast_path <- FLAREr::get_driver_forecast_path(config,
                                                         forecast_model = config$met$forecast_met_model)
  
  if(!is.null(noaa_forecast_path)){
    FLAREr::get_driver_forecast(lake_directory, forecast_path = noaa_forecast_path, config)
    forecast_dir <- file.path(config$file_path$noaa_directory, noaa_forecast_path)
  }else{
    forecast_dir <- NULL
  }
  
  FLAREr::get_stacked_noaa(lake_directory, config, averaged = TRUE)
  met_out <- FLAREr::generate_glm_met_files(obs_met_file = file.path(config$file_path$noaa_directory, "noaa", "NOAAGEFS_1hr_stacked_average", config$location$site_id, paste0("observed-met-noaa_",config$location$site_id,".nc")),
                                            out_dir = config$file_path$execute_directory,
                                            forecast_dir = forecast_dir,
                                            config = config)
  
  #met_out$filenames <- met_out$filenames[!stringr::str_detect(met_out$filenames, "31")]
  #Need to remove the 00 ensemble member because it only goes 16-days in the future
  met_out$filenames <- met_out$filenames[!stringr::str_detect(met_out$filenames, "ens00")]
  
  pars_config <- readr::read_csv(file.path(config$file_path$configuration_directory, config$model_settings$par_config_file), col_types = readr::cols())
  obs_config <- readr::read_csv(file.path(config$file_path$configuration_directory, config$model_settings$obs_config_file), col_types = readr::cols())
  states_config <- readr::read_csv(file.path(config$file_path$configuration_directory, config$model_settings$states_config_file), col_types = readr::cols())
  
  #Create observation matrix
  obs <- FLAREr::create_obs_matrix(cleaned_observations_file_long = file.path(config$file_path$qaqc_data_directory, paste0(config$location$site_id, "-targets-insitu.csv")),
                                   obs_config = obs_config,
                                   config)
  
  full_time <- seq(lubridate::as_datetime(config$run_config$start_datetime), lubridate::as_datetime(config$run_config$forecast_start_datetime) + lubridate::days(config$run_config$forecast_horizon), by = "1 day")
  full_time <- as.Date(full_time)
  
  
  message("Generating forecast")
  states_config <- FLAREr::generate_states_to_obs_mapping(states_config, obs_config)
  
  model_sd <- FLAREr::initiate_model_error(config, states_config)
  
  init <- FLAREr::generate_initial_conditions(states_config,
                                              obs_config,
                                              pars_config,
                                              obs,
                                              config,
                                              historical_met_error = met_out$historical_met_error)
  config
  #Run EnKF
  da_forecast_output <- FLAREr::run_da_forecast(states_init = init$states,
                                                pars_init = init$pars,
                                                aux_states_init = init$aux_states_init,
                                                obs = obs,
                                                obs_sd = obs_config$obs_sd,
                                                model_sd = model_sd,
                                                working_directory = config$file_path$execute_directory,
                                                met_file_names = met_out$filenames,
                                                inflow_file_names = NULL,#list.files(inflow_file_dir, pattern='INFLOW-'),
                                                outflow_file_names = NULL,#list.files(inflow_file_dir, pattern='OUTFLOW-'),
                                                config = config,
                                                pars_config = pars_config,
                                                states_config = states_config,
                                                obs_config = obs_config,
                                                management = NULL,
                                                da_method = config$da_setup$da_method,
                                                par_fit_method = config$da_setup$par_fit_method)
  
  message("Generating netcdf")
  saved_file <- FLAREr::write_forecast_netcdf(da_forecast_output = da_forecast_output,
                                              forecast_output_directory = config$file_path$forecast_output_directory,
                                              use_short_filename = TRUE)
  
  message("Generating csv")
  forecast_file <- FLAREr::write_forecast_csv(da_forecast_output = da_forecast_output,
                                              forecast_output_directory = config$file_path$forecast_output_directory,
                                              use_short_filename = TRUE)
  
  message("Generating plot")
  pdf_file <- FLAREr::plotting_general_2(file_name = saved_file,  #config$run_config$restart_file,
                                         target_file = file.path(config$file_path$qaqc_data_directory, paste0(config$location$site_id, "-targets-insitu.csv")))

  message("Generating scores")
  score_file <- FLAREr::generate_forecast_score(targets_file = file.path(config$file_path$qaqc_data_directory,paste0(config$location$site_id, "-targets-insitu.csv")),
                                                forecast_file =  forecast_file,
                                                output_directory = file.path(lake_directory, "scores", config$location$site_id, config$run_config$sim_name))
  
  
  #source(file.path(lake_directory,"R/simple_plot.R"))
  
  #forecast_file_name <- saved_file #config$run_config$restart_file
  #output_file_name <- paste0(config$file_path$forecast_output_directory, "/", config$run_config$sim_name, "_", config$run_config$forecast_horizon, 'day_simple_plot_', lubridate::date(config$run_config$forecast_start_datetime))
  #qaqc_data_directory <- config$file_path$qaqc_data_directory
  #focal_depths_plotting <- c('0.1', '5', '10')
  
  #simple_file_name <- simple_plot(forecast_file_name,
  #                                output_file_name,
  #                                qaqc_data_directory,
  #                                focal_depths_plotting,
  #                                num_days_plot = 10)
  

  
  rm(da_forecast_output)
  gc()
  
  sink(paste0(lake_directory, '/last_completed_index.txt'))
  print(i)
  sink()
  
}