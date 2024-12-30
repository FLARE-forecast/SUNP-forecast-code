insitu_qaqc_withDO <- function(realtime_file,
                        hist_buoy_file,
                        hist_manual_file,
                        hist_all_file,
                        maintenance_url,
                        variables,
                        cleaned_insitu_file,
                        lake_directory,
                        config){

  # create combined manual and high frequency buoy data file
  library(tidyverse)
  library(lubridate)

  sim_folder <- lake_directory

  # download manual data from zenodo: https://zenodo.org/record/7559434
  manual <- read.csv(hist_manual_file)
  manual_names <- unique(manual$parameter)
  variables


  nms <- unique(manual$parameter)

  if('waterTemperature_degC' %in% nms){
    manual <- manual %>%
      dplyr::filter(parameter %in% c("waterTemperature_degC", "oxygenDissolved_mgl", "oxygenDissolvedPercentOfSaturation_pct")) %>%
      dplyr::mutate(date = as.Date(date)) %>%
      dplyr::select(date, depth_m, parameter, value, station) %>%
      tidyr::pivot_wider(names_from = parameter, values_from = value) %>%
      tidyr::unchop(everything()) # do this bc of strange formatting with pivot wider

    # rename to old names
    manual <- manual %>%
      dplyr::rename(temp_C = waterTemperature_degC,
             DO_mgl = oxygenDissolved_mgl,
             DO_pctsat = oxygenDissolvedPercentOfSaturation_pct)

  }else{
    manual <- manual %>%
      dplyr::filter(parameter %in% c("temp_C", "DO_mgl", "DO_pctsat")) %>%
      dplyr::mutate(date = as.Date(date)) %>%
      dplyr::select(date, depth_m, parameter, value, station) %>%
      tidyr::pivot_wider(names_from = parameter, values_from = value) %>%
      tidyr::unchop(everything()) # do this bc of strange formatting with pivot wider
  }

  manual <- manual %>%
    dplyr::filter(station == 210) %>%  # this is the deep hole site
    dplyr::mutate(time = hms("00:00:00")) %>%
    #dplyr::mutate(DateTime = as.POSIXct(date, format = "%Y-%m-%d %H:%M:%S", tz = 'UTC+5') + 60*60*4) %>%
    dplyr::mutate(DateTime = as.POSIXct(date, format = "%Y-%m-%d %H:%M:%S", tz = 'UTC')) %>%
    dplyr::select(DateTime, depth_m, temp_C, DO_mgl, DO_pctsat, station) %>%
    dplyr::mutate(method = 'manual') %>%
    dplyr::mutate(DO_mmol_m3 = DO_mgl*1000/32) %>% #to convert mg/L (or ppm) to molar units
    dplyr::select(DateTime, depth_m, temp_C, DO_mmol_m3, station, method)


  colnames(manual) <- c('DateTime', 'Depth', 'Temp_manual', 'DO_mmol_m3_manual',  'site', 'method')
  manual$site <- as.character(manual$site)
  manual$DateDepth <- paste0(manual$DateTime, " ", manual$Depth)

  # remove manual observations from depths where buoy obs exist
  manual <- manual %>%
    #dplyr::filter(ifelse(DateTime > as_datetime('2007-01-01', tz = 'America/New_York'), Depth > 12, Depth >0))
    dplyr::filter(ifelse(DateTime > as.POSIXct('2007-01-01 00:00:00'), Depth > 12, Depth >0))


  # and historical high frequency buoy temp data
  # extract midnight measurements only and only observations when buoy is deployed
  field_all <- read.csv(hist_buoy_file[1])
  field_all$datetime <- as.POSIXct(field_all$datetime, format = "%Y-%m-%d %H:%M:%S", tz = 'America/New_York')
  field_all$datetime <- lubridate::with_tz(field_all$datetime, "UTC") # convert EST to UTC
  field_midn <- field_all %>%
    dplyr::mutate(day = day(datetime)) %>%
    dplyr::mutate(hour = hour(datetime)) %>%
    dplyr::mutate(minute = minute(datetime))
  field_midn <- field_midn[field_midn$hour=='0' & field_midn$minute=='0',]
  field_midn <- field_midn[field_midn$location=='loon',]
  field_midn <- field_midn %>% dplyr::select(-location, -day, -minute, -hour)

  # add depth column and remove from column name
  field_format <- data.frame("DateTime" = as.Date(NA),
                             "Depth" = NA,
                             "Temp" = NA)

  depths <- c('0.5', '0.75', '0.85', '1.0', '1.5', '1.75', '1.85', '2.0', '2.5', '2.75',
              '2.85', '3.0', '3.5', '3.75', '3.85', '4.5', '4.75', '4.85', '5.5', '5.75',
              '5.85', '6.5', '6.75', '6.85', '7.5', '7.75', '7.85', '8.5', '8.75', '8.85',
              '9.5', '9.75', '9.85', '10.5', '11.5', '13.5')

  for (i in 1:length(depths)) {
    temp <- field_midn[,c(1, i+1)]
    temp$Depth <- depths[i]
    colnames(temp) <- c('DateTime', 'Temp', 'Depth')
    field_format <- full_join(temp, field_format, by = c('DateTime', 'Temp', 'Depth'))
  }


  # put depth as second column
  field_format <- field_format %>% dplyr::select( 'DateTime', 'Depth', 'Temp') %>%
    dplyr::arrange(DateTime, Depth)

  field_format <- na.omit(field_format)

  field_format$Depth <- as.numeric(field_format$Depth)
  # round depths to nearest integer for matching with DO
  for(i in 1:nrow(field_format)){
    if(field_format$Depth[i] < 1){
      field_format$Depth[i] <- 0.5
    }else if(field_format$Depth[i]==1){
      field_format$Depth[i] <- 1.0
    }else if(field_format$Depth[i]==1.5){
      field_format$Depth[i] <- field_format$Depth[i]
    }else if(field_format$Depth[i] > 1 & field_format$Depth[i] < 2){
      field_format$Depth[i] <- 1.5
    }
    else(field_format$Depth[i] <- ceiling(field_format$Depth[i]))
  }

  field_format$Depth <- as.character(field_format$Depth)

  # and historical high frequency buoy DO data
  # extract midnight measurements only and only observations when buoy is deployed
  field_oxy <- read.csv(hist_buoy_file[2])

  # extract midnight measurements only and only observations when buoy is deployed
  field_oxy$datetime <- as.POSIXct(field_oxy$datetime, format = "%Y-%m-%d %H:%M:%S", tz = "American/New_York")
  field_oxy$datetime <- lubridate::with_tz(field_oxy$datetime, "UTC") # convert EST to UTC
  field_midn_oxy <- field_oxy %>%
    dplyr::mutate(day = day(datetime)) %>%
    dplyr::mutate(hour = hour(datetime)) %>%
    dplyr::mutate(minute = minute(datetime))
  field_midn_oxy <- field_midn_oxy[field_midn_oxy$hour=='0' & field_midn_oxy$minute=='0',]
  field_midn_oxy <- field_midn_oxy[field_midn_oxy$location=='loon',]
  field_midn_oxy <- field_midn_oxy %>% dplyr::select(-location, -day, -minute, -hour)

  # add depth column and remove from column name
  # DO upper is at 1.5m
  # DO lower is at 10.5m
  # metadata on edi: https://portal.edirepository.org/nis/mapbrowse?packageid=edi.499.2

  depths <- c('1.5', '10.5')

  oxy <- field_midn_oxy[,c(1, 2, 3, 5)]
  oxy$Depth <- 1.5
  colnames(oxy) <- c('DateTime', 'DOSat', "DOppm", 'Flag', 'Depth')

  oxy_2 <- field_midn_oxy[,c(1, 6, 7, 9)]
  oxy_2$Depth <- 10.5
  colnames(oxy_2) <- c('DateTime', 'DOSat', "DOppm", 'Flag', 'Depth')

  field_format_oxy <- dplyr::full_join(oxy, oxy_2)


  # put depth as second column
  field_format_oxy <- field_format_oxy %>% dplyr::select( 'DateTime', 'Depth', 'DOppm', 'Flag')
  field_format_oxy <- field_format_oxy %>%
    dplyr::arrange(DateTime, Depth)

  # round depths to match temp depths
  field_format_oxy <- field_format_oxy %>%
    #  mutate(depth_cor = ifelse(Depth==1.5, 1.0, Depth)) %>%
    dplyr::mutate(depth_cor = ifelse(Depth==10.5, 10.0, Depth)) %>%
    dplyr::mutate(Depth = depth_cor) %>%
    dplyr::select(-depth_cor)


  # remove some data with flags
  field_format_oxy <- field_format_oxy[field_format_oxy$Flag != 'm' & field_format_oxy$Flag !='mcep', ]
  field_format_oxy <- na.omit(field_format_oxy)
  field_format_oxy$Depth <- as.character(field_format_oxy$Depth)
  field_format_oxy <- field_format_oxy %>%
    dplyr::select(-Flag) %>%
    dplyr::mutate(DO_mmol_m3 = DOppm*1000/32) #to convert mg/L (or ppm) to molar units

  # combine historical temp and DO buoy data
  buoy <- dplyr::left_join(field_format, field_format_oxy)
  buoy$DateTime <- as.POSIXct(buoy$DateTime)
  buoy$site <- as.character('210') # set up buoy site to 210?
  buoy$method <- 'buoy'
  colnames(buoy) <- c('DateTime', 'Depth', 'Temp_buoy', 'DOppm_buoy', 'DO_mmol_m3_buoy', 'site', 'method')
  #buoy <- na.omit(buoy)
  buoy$DateDepth <- paste0(buoy$DateTime, " ", buoy$Depth)
  buoy$Depth <- as.numeric(buoy$Depth)


  # remove days from buoy dataset where there is manual data
  remove <- manual$DateTime
  buoy <- buoy[!buoy$DateTime %in% remove,  ]


  # combine the two datasets
  temp_data <- dplyr::full_join(manual, buoy)

  data_nodups <- temp_data[!duplicated(temp_data[,1:2]),]

  table(duplicated(data_nodups[,1:2]))
  table(duplicated(temp_data[,1:2]))

  #ggplot(data_nodups[data_nodups$DateTime > '2018-01-01 00:00:00' & data_nodups$DateTime < '2019-01-01 00:00:00',], aes(x = DateTime, y = Temp_buoy)) +
  #  geom_line() +
  #  geom_line(aes(x= DateTime, y = Temp_manual, col = 'red'))


  #ggplot(buoy[buoy$DateDepth > '2018-01-01 00:00:00' & buoy$DateDepth < '2019-01-01 00:00:00',], aes(x = DateTime, y = Temp_buoy)) +
  #  geom_line(aes(col = as.factor(Depth)))

  #ggplot(manual[manual$DateDepth > '2018-01-01 00:00:00' & manual$DateDepth < '2019-01-01 00:00:00',], aes(x = DateTime, y = Temp_manual)) +
  #  geom_line(aes(col = as.factor(Depth)))

  data_nodups <- data_nodups %>%
    dplyr::mutate(Temp = ifelse(is.na(Temp_manual), Temp_buoy, Temp_manual)) %>%
    dplyr::mutate(DO = ifelse(is.na(DO_mmol_m3_manual), DO_mmol_m3_buoy, DO_mmol_m3_manual)) %>%
    dplyr::select(DateTime, Depth, Temp, DO) %>%
    dplyr::arrange(DateTime, Depth)


  write.csv(data_nodups, hist_all_file, row.names = FALSE)


  # now combine the historical manual + buoy data with the realtime file
  d_head<-read.csv(realtime_file, skip=1, as.is=T) #get header minus wonky Campbell rows
  d <-read.csv(realtime_file, skip=4, header=F) #get data minus wonky Campbell rows
  names(d)<-names(d_head) #combine the names to deal with Campbell logger formatting

  #Removes row if the TIMESTAMP column is blank
  d <- d[complete.cases(d$TIMESTAMP),]

  #Removes row if the RECORD column has an NA or blank
  d <- d[!(is.na(d$RECORD) | d$RECORD==""), ]


  # convert to UTC
  #d$TIMESTAMP <- as.POSIXct(d$TIMESTAMP)
  attr(d$TIMESTAMP, "tzone") <- "UTC"

  # remove data from before buoy was deployed
  d <- d[d$TIMESTAMP > '2021-06-07 00:00:00',]

  # remove days where maintenance occurred
  maint <- gsheet::gsheet2tbl(maintenance_url)
  maint$colnumber <- NA
  maint$TIMESTAMP_start <- as.POSIXct(maint$TIMESTAMP_start)
  maint$TIMESTAMP_end <- as.POSIXct(maint$TIMESTAMP_end)
  attr(maint$TIMESTAMP_start, "tzone") <- "UTC"
  attr(maint$TIMESTAMP_end, "tzone") <- "UTC"


  for(i in 1:nrow(maint)){

    #print(i)

    # get start and end time of one maintenance event
    start <- maint$TIMESTAMP_start[i]
    end <- maint$TIMESTAMP_end[i]
    if(is.na(end)){
      end <- as.POSIXct(Sys.time())
      attr(end, "tzone") <- "UTC"
    }

    # set colnumbers for maintenance events
    if(maint$instrument[i]=='ALL'){
      maint$colnumber[i] <- 'c(6:38)'
    }
    if(maint$instrument[i]=='EXO'){
      maint$colnumber[i] <- 'c(17:35)'
    }
    if(maint$instrument[i]=='temp'){
      maint$colnumber[i] <- 'c(6:16)'
    }
    if(maint$instrument[i]=='do'){
      maint$colnumber[i] <- 'c(36:38)'
    }

    if(grepl("^\\d+$", maint$colnumber[i])) # single num
    {
      maintenance_cols <- intersect(c(2:38), as.integer(maint$colnumber[i]))
    }
    else if(grepl("^c\\(\\s*\\d+\\s*(;\\s*\\d+\\s*)*\\)$", maint$colnumber[i])) # c(x;y;...)
    {
      maintenance_cols <- intersect(c(2:38), as.integer(unlist(regmatches(maint$colnumber[i],
                                                                          gregexpr("\\d+", maint$colnumber[i])))))
    }
    else if(grepl("^c\\(\\s*\\d+\\s*:\\s*\\d+\\s*\\)$", maint$colnumber[i])) # c(x:y)
    {
      bounds <- as.integer(unlist(regmatches(maint$colnumber[i], gregexpr("\\d+", maint$colnumber[i]))))
      maintenance_cols <- intersect(c(2:38), c(bounds[1]:bounds[2]))
    }

    else
    {
      warning(paste("Could not parse column colnumber in row", i, "of the maintenance log. Skipping maintenance for",
                    "that row. The value of colnumber should be in one of three formats: a single number (\"47\"), a",
                    "semicolon-separated list of numbers in c() (\"c(47;48;49)\"), or a range of numbers in c() (\"c(47:74)\").",
                    "Other values (even valid calls to c()) will not be parsed properly."))
      next
    }

    # remove EXO_Date and EXO_Time columns from the list of maintenance columns, because they will be deleted later
    maintenance_cols <- setdiff(maintenance_cols, c(17, 18))

    if(length(maintenance_cols) == 0)
    {
      warning(paste("Did not parse any valid data columns in row", i, "of the maintenance log. Valid columns have",
                    "indices 2 through 38, excluding 17 and 18, which are EXO Date and time columns and are deleted by this script.
                    Skipping maintenance for that row."))
      next
    }
    # replace relevant data with NAs and set "all" flag while maintenance was in effect
    d[d$TIMESTAMP >= start & d$TIMESTAMP <= end, maintenance_cols] <- NA
  }

  # convert depth columns into long format

  temp_format <- data.frame(matrix(ncol=length(variables) + 1), nrow = 0)
  colnames(temp_format) <- c('DateTime', 'Depth', variables)
  #temp_format$DateTime <- as.POSIXct(temp_format$DateTime)


  depths <- c('0.1', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10')

  for (i in 1:length(depths)) {
    temp <- d[,c(1, i+5)]
    #temp$DateTime <- as.POSIXct(temp$DateTime, tryFormats = c("%Y-%m-%d %T", "%Y-%m-%d"))
    temp$Depth <- depths[i]
    colnames(temp) <- c('DateTime', 'Temp', 'Depth')
    temp_format <- dplyr::full_join(temp, temp_format)
  }

  # put depth as second column and sort by date and depth
  temp_format <- temp_format %>%
    dplyr::mutate(Depth = as.numeric(Depth)) %>%
    dplyr::select( 'DateTime', 'Depth', 'Temp') %>%
    dplyr::arrange(DateTime, Depth)

  # pull out oxygen data from QAQC'ed current buoy file

  # temp_oxy <- d %>%
  #   dplyr::select(TIMESTAMP, doobs_1, doobs) %>%
  #   dplyr::rename(DateTime = TIMESTAMP,
  #                 DO_1 = doobs_1,
  #                 DO_10 = doobs)

  temp_oxy <- d %>%
    dplyr::select(TIMESTAMP, doobs_mid, doobs_deep) %>%
    dplyr::rename(DateTime = TIMESTAMP,
                  DO_1 = doobs_mid,
                  DO_10 = doobs_deep)

  oxy_1 <- temp_oxy %>%
    dplyr::select(DateTime, DO_1) %>%
    dplyr::mutate(Depth = 1.0) %>%
    dplyr::rename(DO = DO_1)

  oxy_10 <- temp_oxy %>%
    dplyr::select(DateTime, DO_10) %>%
    dplyr::mutate(Depth = 10.0) %>%
    dplyr::rename(DO = DO_10)

  oxy_10$DO <- as.numeric(oxy_10$DO)

  oxy_buoy <- dplyr::full_join(oxy_1, oxy_10) %>%
    dplyr::mutate(DO = DO*1000/32) # convert from mg/L to mmol/m3

  # join with QAQC'ed current temp data from buoy
  temp_oxy_buoy <- dplyr::full_join(oxy_buoy, temp_format) %>%
    dplyr::select(DateTime, Depth, Temp, DO)

  # remove data from when the buoy is in the harbor and the 10m DO
  # remains connected (obs show up but are not 10m obs bc buoy is in the harbor)
  temp_oxy_buoy <- temp_oxy_buoy %>%
    mutate(DO = ifelse(is.na(Temp) & !is.na(DO), NA, DO))

  temp_oxy_buoy <- na.omit(temp_oxy_buoy)

  # combine with historical data
  h <- read.csv(hist_all_file)
  #h$DateTime <- as.POSIXct(h$DateTime)
  attr(h$DateTime, "tzone") <- "UTC"


  dh <- rbind(h, temp_oxy_buoy)
  attr(dh$DateTime, "tzone") <- "UTC"


  # extract midnight observations
  dh <- dh %>%
    dplyr::mutate(date = lubridate::date(DateTime),
                  hour = lubridate::hour(DateTime),
                  depth = Depth) %>%
    dplyr::filter(hour == 0) %>%
    dplyr::group_by(date, depth, hour) %>%
    dplyr::mutate(temperature = mean(Temp, na.rm = TRUE)) %>% # take the average for each hour, data is every ten minutes
    dplyr::mutate(oxygen = mean(DO, na.rm = TRUE)) %>%
    dplyr::distinct(date, depth, .keep_all = TRUE)

  # put into FLARE format
  dh <- dh %>%
    dplyr::select(-c(Depth, Temp)) %>%
    tidyr::pivot_longer(cols = variables, names_to = 'variable', values_to = 'value') %>%
    dplyr::mutate(time = as.POSIXct(DateTime),
                  site_id = 'sunp') %>%
    dplyr::ungroup() %>%
    dplyr::select(time, site_id, depth, value, variable) %>%
    dplyr::rename(datetime = time, observation = value)

  dh <- na.omit(dh)
  dh$datetime <- lubridate::force_tz(dh$datetime, "UTC") # extra measure just to make sure
  #attr(dh$time, "tzone") <- "UTC"
  #dh$time <- dh$time - 60*60*4

  # combine historial and real-time data


  # quick fix to set all hours to 0 to match with `FLAREr::combine_forecast_observations` function
  #dh$hour <- as.numeric(0)

  if(!dir.exists(dirname(cleaned_insitu_file))){
    dir.create(dirname(cleaned_insitu_file), recursive = TRUE)
  }

  readr::write_csv(dh, cleaned_insitu_file)

  return(cleaned_insitu_file)
}
