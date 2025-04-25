library(dplyr)
#library(minioclient)
library(weather)
library(ggplot2)
#library(jpeg)
library(patchwork)
library(cowplot)

#forecast_date <- Sys.Date()
forecast_date <- Sys.Date() - lubridate::days(1)
noaa_date <- Sys.Date() - lubridate::days(2)

# met_forecast_s3 <- arrow::s3_bucket(file.path("bio230121-bucket01/flare/drivers/met/gefs-v12/stage2",paste0("reference_datetime=",noaa_date),"site_id=sunp"),
#                            endpoint_override = 'renc.osn.xsede.org',
#                            anonymous = TRUE)
#
# # grab 8 day forecast (including today)
#
# #daily mean high and mean low
# met_forecast_df_mean_extremes <- arrow::open_dataset(met_forecast_s3) |>
#   filter(variable == 'air_temperature') |>
#   collect() |>
#   filter(datetime < (noaa_date + lubridate::days(8))) |>
#   mutate(date = as.Date(datetime)) |>
#   group_by(date,parameter) |>
#   summarise(day_min = min(prediction),
#             day_max = max(prediction)) |>
#   ungroup() |>
#   group_by(date) |>
#   summarise(mean_min = mean(day_min),
#             mean_max = mean(day_max)) |>
#   ungroup() |>
#   mutate(mean_min = (round(((mean_min - 273.15) * (9/5) + 32), digits = 1)),
#          mean_max = (round(((mean_max - 273.15) * (9/5) + 32), digits = 1))) |>
#   filter(date >= forecast_date)


# ## daily forecast for NOON temperatures with CI
# met_forecast_df_max_uncertainty <- arrow::open_dataset(met_forecast_s3) |>
#   filter(variable == 'air_temperature') |>
#   collect() |>
#   mutate(time = format(as.POSIXct(datetime), format = "%H:%M")) |>
#   filter(datetime < (noaa_date + lubridate::days(9)),
#          time == '12:00') |>
#   mutate(date = as.Date(datetime),
#          prediction = (round(((prediction - 273.15) * (9/5) + 32), digits = 1))) |>
#   group_by(date) |>
#   summarise(noon_mean = mean(prediction),
#             noon_sd = sd(prediction),
#             noon_se = noon_sd / sqrt(n()),
#             noon_CI_lower = noon_mean - (1.96 * noon_se),
#             noon_CI_upper = noon_mean + (1.96 * noon_se)) |>
#   ungroup() #|>
#   # group_by(date) |>
#   # summarise(mean_min = mean(day_min),
#   #           mean_max = mean(day_max)) |>
#   # ungroup() |>
#   # mutate(mean_min = (round(((mean_min - 273.15) * (9/5) + 32), digits = 1)),
#   #        mean_max = (round(((mean_max - 273.15) * (9/5) + 32), digits = 1)))

#mc_ls(paste0("s3_store/",'bio230121-bucket01/flare/forecasts/parquet/site_id=sunp/model_id=glm_flare_v1/',paste0("reference_date=",forecast_date)))

flare_forecast_s3 <- arrow::s3_bucket(file.path('bio230121-bucket01/flare/forecasts/parquet/site_id=sunp/model_id=glm_flare_v1',paste0("reference_date=",forecast_date)),
                                    endpoint_override = 'amnh1.osn.mghpcc.org',
                                    anonymous = TRUE)

flare_forecast_df <- arrow::open_dataset(flare_forecast_s3) |>
  filter(variable == 'temperature',
         depth == 0.1) |>
  collect() |>
  filter(datetime < (forecast_date + lubridate::days(8))) |>
  mutate(date = as.Date(datetime),
         prediction = (round(((prediction) * (9/5) + 32), digits = 1))) |>
  group_by(date) |>
  summarise(mean = mean(prediction),
            median = round(median(prediction), digits = 1),
            sd = sd(prediction),
            CI_upper = quantile(prediction, 0.975),
            CI_lower = quantile(prediction, 0.025)) |>
            #se = sd / sqrt(n()),
            #CI_lower = mean - (1.96 * se),
            #CI_upper = mean + (1.96 * se)) |>
  ungroup() |>
  filter(date >= forecast_date,
         date < (forecast_date + lubridate::days(7)))

#0	Clear sky
#1, 2, 3	Mainly clear, partly cloudy, and overcast
#45, 48	Fog and depositing rime fog
#51, 53, 55	Drizzle: Light, moderate, and dense intensity
#56, 57	Freezing Drizzle: Light and dense intensity
#61, 63, 65	Rain: Slight, moderate and heavy intensity
#66, 67	Freezing Rain: Light and heavy intensity
#71, 73, 75	Snow fall: Slight, moderate, and heavy intensity
#77	Snow grains
#80, 81, 82	Rain showers: Slight, moderate, and violent
#85, 86	Snow showers slight and heavy
#95 *	Thunderstorm: Slight or moderate
#96, 99 *	Thunderstorm with slight and heavy hail

weather_description <- data.frame(code = as.character(c(0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99)),
                                  description = c('day-sunny', #0
                                                  'day-sunny-overcast', #1
                                                  'day-cloudy', #2
                                                  'cloudy', #3
                                                  'day-fog', #45
                                                  'fog', #48
                                                  'day-showers', #51
                                                  'rain', #53
                                                  'rain', #55
                                                  'day-sleet', #56
                                                  'sleet', #57
                                                  'day-rain', #61
                                                  'rain', #63
                                                  'rain', #65
                                                  'day-sleet', #66
                                                  'sleet', #67
                                                  'day-snow-wind', #71
                                                  'snow', #73
                                                  'snow', #75
                                                  'snow', #77
                                                  'day-rain', #80
                                                  'rain', #81
                                                  'rain', #82
                                                  'day-snow-wind', #85
                                                  'snow', #86
                                                  'thunderstorm', #95
                                                  'thunderstorm', #96,
                                                  'thunderstorm' #99
                                                  ))

# forecast_weather_code <- read.csv("https://api.open-meteo.com/v1/forecast?latitude=43.4&longitude=-72.05&daily=weather_code&timezone=America%2FNew_York&format=csv") |>
#   rename(date = latitude, code = longitude) |>
#   select(date, code) |>
#   slice(3:9) |>
#   left_join(weather_description, by = 'code') |>
#   mutate(description = ifelse(is.na(description),'na',description))


met_forecast_df <- readr::read_csv('https://api.open-meteo.com/v1/forecast?latitude=43.39102&longitude=-72.053627&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=America%2FNew_York&models=gfs_seamless&format=csv') |>
  rename(date = latitude, code = longitude, airtemp_min = utc_offset_seconds, airtemp_max = elevation) |>
  select(date, code, airtemp_min, airtemp_max) |>
  slice(3:9) |>
  left_join(weather_description, by = 'code') |>
  mutate(description = ifelse(is.na(description),'na',description),
         airtemp_min = (round(((as.numeric(airtemp_min)) * (9/5) + 32))),
         airtemp_max = (round(((as.numeric(airtemp_max)) * (9/5) + 32))))

plotting_frame <- data.frame(height = seq.int(1,100), width = seq.int(1,400))

water_temp_range <- flare_forecast_df |>
  select(date, CI_lower, CI_upper) |>
  mutate(watertemp_text = paste0(format(round(CI_lower, digits = 1), nsmall = 1), ' - ', format(round(CI_upper, digits = 1), nsmall = 1))) |>
  mutate(height = 36,
         width = c(53, 108, 162, 215, 270, 323, 377))

water_temp_median <- flare_forecast_df |>
  select(date, median) |>
  mutate(median = format(round(median, digits = 1), nsmall = 1)) |>
  mutate(height = 40,
         width = c(53, 108, 162, 215, 270, 323, 377))

air_temps <- met_forecast_df |>
  mutate(airtemp_text = paste0(round(airtemp_min), ' - ', round(airtemp_max))) |>
  select(date, airtemp_text) |>
  mutate(height = 57,
         width = c(55, 110, 162, 217, 270, 324, 379))



weather_icons <- met_forecast_df |>
  select(date,description) |>
  mutate(#height = 62, ## USE THESE FOR RUNNING LOCALLY - NOT ON GH
         #width = c(39, 95, 147, 203, 254, 308, 362), ## USE THESE FOR RUNNING LOCALLY - NOT ON GH
         height = 67,
         width = c(55, 110, 162, 217, 270, 324, 379))


day_df <- weather_icons |>
  mutate(weekday = weekdays(as.Date(date))) |>
  select(weekday, date) |>
  mutate(height = 22,
         width = c(55, 108, 162, 217, 270, 325, 378))

day_df$weekday[1] <- 'Today'

date_df <- day_df |>
  mutate(month = lubridate::month(as.Date(date, format="%Y-%m-%d")),
         month_abbr = month.abb[month],
         #month_name = months(as.Date(date, format="%Y-%m-%d")),
         day = lubridate::day(as.Date(date, format="%Y-%m-%d")),
         year = lubridate::year(as.Date(date, format="%Y-%m-%d"))) |>
  mutate(date_value = paste(day, month_abbr, year)) |>
  select(date_value) |>
  mutate(height = 18,
         width = c(55, 108, 162, 217, 270, 325, 379))

img_overlay <- ggplot(plotting_frame, aes(width, height)) +
  geom_weather(data = weather_icons, aes(width, height, weather = description), size = 8) +
  geom_text(data = water_temp_range, aes(x = width, y = height, label = watertemp_text), size = 1.6, fontface = 'bold', family = 'Ariel') +
  geom_text(data = water_temp_median, aes(x = width, y = height, label = median), size = 2.2, fontface = 'bold', family = 'Ariel') +
  geom_text(data = air_temps, aes(x = width, y = height, label = airtemp_text), size = 2.2, fontface = 'bold', family = 'Ariel') +
  geom_text(data = day_df, aes(x = width, y = height, label = weekday), size = 2, fontface = 'bold', family = 'Ariel') +
  geom_text(data = date_df, aes(x = width, y = height, label = date_value), size = 1.5, fontface = 'bold', family = 'Ariel') +
  xlim(1,400) +
  ylim(1,100) +
  theme_cowplot() +
  theme(axis.line=element_blank(),axis.text.x=element_blank(),
        axis.text.y=element_blank(),axis.ticks=element_blank(),
        axis.title.x=element_blank(),
        axis.title.y=element_blank(),legend.position="none",
        panel.background=element_blank(),panel.border=element_blank(),panel.grid.major=element_blank(),
        panel.grid.minor=element_blank(),plot.background=element_blank())

#img_overlay

forecast_plot <- ggdraw() +
  #draw_image("data_viz_swim/SunapeeVis2.jpeg", scale = 0.75, width = 1.1, height = 1, x = 0) +
  draw_image("data_viz_swim/SunapeeVis5.jpeg", scale = 0.95, width = 1, height = 1, x = -0.01) +
  draw_plot(img_overlay)

ggsave(filename = 'data_viz_swim/sunp_forecast_plot.jpeg', plot = forecast_plot ,width = 5, height = 3)

