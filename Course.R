# C. A. Pozniak: Geospatial Code Overview #
#  11th July, 2024 | La Paz, Bolivia #

if (!require("pacman")) install.packages("pacman")

library(pacman)

p_load( tidyverse,
        archive,
        sf,
        tmap,
        wbstats,
        rnaturalearth,
        rnaturalearthdata,
        readxl,
        mapdeck,
        usethis,
        httr,
        janitor)


### Introduction: ###


#### Map 1: Using the World Bank API ####

# WDI LINK: https://databank.worldbank.org/source/world-development-indicators

# Choose an indicator you like from the link above. 
# Find it through 'series' and clicking on the metadata.

ind <- "NY.GDP.MINR.RT.ZS"

# Check you have a good indicator. This information will be used later.
indicator_info <- filter(wb_cachelist$indicators, indicator_id == ind)

# Load the countries from "R Natural Earth" 
data <- ne_countries() 

# Load the World Bank Data
# mrnev shows you the most recent non-zero value for each country. Rename the column.

wb_data <- wb_data(
  c(mineral_rents = ind), 
  mrnev = 1)

# Join the data with NE country information.
# Check the codes. Remove ATA for a nicer map

join_data <- left_join(data, wb_data,
                       by = c("iso_a3_eh" = "iso3c")) %>% 
  filter(iso_a3 != "ATA")
head(join_data)

# Plot through ggplot 
ggplot(join_data, aes(fill = mineral_rents)) +
  geom_sf() +
  theme(legend.position="bottom") +
  labs(
    title = indicator_info$indicator,
    fill = NULL,
    caption = paste("Source:", indicator_info$source_org))

# A shorter and more elegant way to do it:
data <- data %>% 
  left_join(
    wb_data(
      c(mineral_rents = ind), 
      mrnev = 1),
    by = c("iso_a3" = "iso3c")
  ) %>%
  filter(iso_a3 != "ATA")

#### MAP 2: Sub-national Map of Bolivia ####
  
#Subnational maps through Natural Earth #

bol_sub_data <- ne_states(country = "bolivia")
glimpse(bol_sub_data)


### Load internal socioeconomic data: https://celade.cepal.org/bdcelade/depualc/
### Have a look at this file in Excel. It's human readable, not very machine readable. 
### This is a mess -- let's pick the columns and rows we want.

literacy <- read_excel('bo_educ_2012.xlsx') %>% 
  slice(-1:-11) %>% 
  dplyr::select(1, 8) %>% 
  rename(name = 1, literacy_rate = 2) 

# This is trying to be clever, but is just an example of how we can clean messy excel data.
literacy <- literacy %>%
  mutate(literacy_rate = ifelse(name == "Población total", literacy_rate, NA),
         name = ifelse(name == "BENI", "EL BENI", name)) %>%
  fill(literacy_rate, .direction = "up") %>%
  filter(!is.na(name) & name == toupper(name))



# So what are we looking for in our subnational dataset? We're looking for: names, shapes, locations.
bol_sub <- bol_sub_data %>% 
  dplyr::select(name, woe_name, latitude, longitude, geometry) %>% 
# I will use this departamentos dataset to be able to inner-merge by only the actual names, so I'm capitalizing the names for joining.
  mutate(name = toupper(name),
         )

# Now, I join so we only have the departamentos names and the relevant informaton
join_literacy <- literacy %>% 
  inner_join(bol_sub %>% dplyr::select(name, woe_name, latitude, longitude, geometry), by = "name") %>% 
# This then calculates the center of each shape so we have somewhere to attach the labels to. 
  mutate(
    centroid = st_centroid(geometry),
    centroid_coords = st_coordinates(centroid),
    centroid_x = centroid_coords[,1],
    centroid_y = centroid_coords[,2])
  

# Let's take a look at this data now.
head(join_literacy)

# Plot the map with literacy rates
ggplot(data = join_literacy) +
  geom_sf(aes(fill = as.numeric(literacy_rate), geometry = geometry)) +
  geom_text(aes(x = centroid_x, y = centroid_y, label = woe_name), size = 2.5, color = "black") +  # Add labels
  scale_fill_viridis_c(option = "magma", name = "Literacy Rate", begin = 0.6, end = 1) +  # Adjust color scale
  theme_minimal() +
  labs(
    title = "Subnational Literacy Rates in Bolivia",
    caption = "Source: Bolivia Census Data"
  ) +
  theme(
    plot.title = element_text(hjust = 0.5),
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank()
  ) 


### MAP 3: Interactive

# Run this first code and enter your MAPBOX token as "MAPBOX = ... " 
edit_r_environ()

# This will allow you to make calls to your API token. 
set_token(Sys.getenv("MAPBOX"))


### Bolivian City Long-Lat Data https://celade.cepal.org/bdcelade/mialc/ciudades/bol/bol2012/xls/bol-2012-C5MB.XLSX
url <- 'https://simplemaps.com/static/data/country-cities/bo/bo.csv'
city_info <- read.csv(url)

# Download the Bolivian internal migration data from here: https://celade.cepal.org/bdcelade/mialc/ciudades/bol/bol2012/xls/bol-2012-C5MB.XLSX
# Importing this gave us weird column names. slice() still keeps the names. Rename as follows:
mig <- read_excel("bol-2012-C5MB.XLSX") %>% 
  row_to_names(row_number = 2) 

# Rename the First Column, R doesn't like empty column names. 
names(mig)[1] <- "name"

# Trim the Data, get rid of 'other' to 'other'.
mig <- mig %>% 
  slice(-30:-n()) %>% 
  filter(name != "Otro") %>% 
  dplyr::select(-Otro)

# Build the list of unique cities to merge with our city information csv. 
unique_cities <- unique(mig$name)

# This merges the city data with the long/lat from our csv above. 
cities <- data.frame(name = unique_cities) %>% 
  inner_join(city_info, by = c('name' = 'city')) %>% 
  dplyr::select(name, lng, lat)

# Essential to convert the dataframe from wide to long. 
mig_long <- mig %>%
  gather(key = "end_city", value = "quantity", -name) %>%
  rename(start_city = name)

# Making sure that we remove the blanks and that the numbers are correctly formatted
mig_long$quantity <- as.numeric(mig_long$quantity, na.rm = TRUE)


# Merge the long dataframe with coordinates dataframe to get start and end coordinates for each city. 
final_mig <- mig_long %>%
  left_join(cities, by = c("start_city" = "name")) %>%
  rename(start_lat = lat, start_lon = lng) %>%
  left_join(cities, by = c("end_city" = "name")) %>%
  rename(end_lat = lat, end_lon = lng) %>% 
  filter(start_city != end_city) %>% 
  mutate(log_quantity = log10(quantity + 1)) %>% 
  filter(complete.cases(.)) 


# Display the final dataframe
print(final_mig)

# This is Mapdeck, the Mapbox R package. It's similar to ggplot.
mapdeck(style = mapdeck_style('dark')) %>%
  add_arc(
    data = final_mig, 
    origin = c("start_lon", "start_lat"),
    destination = c("end_lon", "end_lat"),
    stroke_to = "end_city",
    layer_id = 'arclayer',
    stroke_width = 'log_quantity'
  )


