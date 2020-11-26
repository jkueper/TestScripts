# this script sets up a skeleton for connecting to the aohc database on blackwell 
# and for performing SQL queries that pull data from the database into RStudio environment 
# there are three example queries included with the results pasted in with comments 
# each of these queries uses a separate "syntax" for accessing the database 
# the end of the script include information about missingness 
# note that these are all just examples and may not be the best way to do things 

# libraries needed to connect to the database
# might need to install them (I forget if one of these is deprecated now/merged into maria)
library(RMariaDB)
library(dbConnect)
library(rstudioapi)
library(dplyr)

#########################################################
# Part 1: set up connection to the database 
#########################################################

# set up connection object 
con <- dbConnect(RMariaDB::MariaDB(),
                 dbname = "aohc",
                 host = "blackwell.csd.uwo.ca",
                 user = #"YOUR USER NAME HERE",
                 password = rstudioapi::askForPassword("Database password")) # this is not the same pwd as for blackwell 


#########################################################
# Part 2: examples of accessing the data and pulling into R
#########################################################

# EXAMPLE 1: getting a numerical count of something directly from the database 
# Syntax ex: direct pull where data manipulation is done with sql; nothing is stored in environment 
# get count of client in the characteristics table 
dbGetQuery(con, "select count(distinct CLIENT_KEY) from DIM_CLIENT;") #671994



# EXAMPLE 2: select an entire table from the database
# Syntax example: save a string object that contains the sql query and refer to it later on  
# this pulls in the entire client characteristic table and saves it in your environment 
sqlDIM <- "select * from DIM_CLIENT;" 
DIM_CLIENT <- dbGetQuery(con, sqlDIM)

# now we can do some stuff in R with the df
dim(DIM_CLIENT) # 671994     19
n_distinct(DIM_CLIENT$CLIENT_KEY) #671994 length of table matches num clients 
colnames(DIM_CLIENT)
# what columns are there (should match database schema )
#"CHC_KEY"               "CHC_NAME"              "CLIENT_KEY"            "FSA"                  
# "YEAR_OF_BIRTH"         "SEX"                   "LANGUAGE"              "COUNTRY"              
# "EDUCATION"             "RESIDENCE_TYPE"        "HOUSEHOLD_COMPOSITION" "HOUSEHOLD_INCOME"     
# "PEOPLE_SUPPORTED"      "GENDER_IDENTITY"       "SEXUAL_ORIENTATION"    "RACIAL_ETHNIC_GROUP"  
# "SENSE_OF_COMMUNITY"    "SELF_RATED_PHYSICAL"   "SELF_RATED_MENTAL"  

# look at a summary of residence type frequency counts 
# you can see in the results that there are multiple values that are "missing" information 
# at the end of the script I have included the missingness dictionary I use to condense these during data cleaning
table(DIM_CLIENT$RESIDENCE_TYPE) 
#               homeless/no address        not homeless     other temporary             shelter 
# 209301               11596              445002                1096                2572 
# Undefined             Unknown 
# 121                2306 


# remove the object from the environment
# removing objects after you are done with them helps 
# 1) keep your environment clean and 2) frees up working memory 
remove(DIM_CLIENT)



# EXAMPLE 3: select a subset of data to pull and save as df in R environment 
# syntax ex: embed the sql query in the database connection function 
# this is selecting all columns from the service event table 
# where the event was 1) with a NP or MD and 2) of type blank or encounter 
# condition 1 is from in the providers table; info 2 is from the event table 
# need to join those two tables on the primary key (client key, chc key to get unique clients)
# and on event key to get unique events 
# Note: these conditions make up the proxy I am currently using to identify "ongoing primary care clients" 
sqlOPCC2 <-  dbGetQuery(con, "select DIMCS.* from DIM_CLIENT_SERVICE_EVENT DIMCS inner join
                        (SELECT FIPI.CLIENT_KEY, FIPI.CHC_KEY, FIPI.EVENT_KEY FROM 
                        FACT_INT_PROVIDERS_INVOLVED FIPI WHERE FIPI.PROVIDER_TYPE in 
                        ('Nurse Practitioner (Rn-Ec)', 'Physician', 'Senior Nurse/Np')) FIPI2 ON 
                        (DIMCS.CLIENT_KEY = FIPI2.CLIENT_KEY and 
                        DIMCS.CHC_KEY = FIPI2.CHC_KEY and 
                        DIMCS.EVENT_KEY = FIPI2.EVENT_KEY) where 
                        DIMCS.EVENT_TYPE in ('', 'Encounter');")


# running that query may take several minutes 

# now do stuff with the df in R 
# check dimensions 
dim(sqlOPCC2) # 7116162       7

# number of unique clients 
n_distinct(sqlOPCC2$CLIENT_KEY) # number OPCC clients: 331109

# number of records 
length(sqlOPCC2$EVENT_KEY) # length of event key column (also length of table): 7116162
# number of unique events 
n_distinct(sqlOPCC2$EVENT_KEY) # number of unqiue events; some show up > 1: 7092097

# check the column names 
colnames(sqlOPCC2)
#"CHC_KEY"        "CLIENT_KEY"     "EVENT_KEY"      "EVENT_TYPE"     "CONTACT_DATE"   "EFFECTIVE_DATE" "autoInc" 

# autoInc can be removed; it was used to set up the database 
sqlOPCC2 <- sqlOPCC2 %>%
  select(!c(autoInc))
# check it's done
colnames(sqlOPCC2) # "CHC_KEY"        "CLIENT_KEY"     "EVENT_KEY"      "EVENT_TYPE"     "CONTACT_DATE"   "EFFECTIVE_DATE"
dim(sqlOPCC2) # 7116162       6

# remove the object from the environment
remove(sqlOPCC2)



#########################################################
# Part 3: skeleton code for SQL queries 
#########################################################
# these are some of the most common types of pulls I make 
# can just switch out the capitalized words with what you want 

# Example of pulling in specified column names from a single table 
sqlSkeleton <- "select COLUMN_NAMES from TABLE;" 

# Example of pulling in specific column names from a single table with conditions 
sqlSkeleton2 <- "select COLUMN_NAMES from TABLE where CONDITIONS;"


# Example: join two tables with and conditions, where the desired data to pull in come from the first table only
# note the sqlOPCC2 pull example above follows a different structure that renames tables and  
# applies selections and conditions to the second table before joining with the first table 
# the strategy for sqlOPCC2 can be more efficient and cleaner, but isn't necessary 
sqlSkeleton3 <- "select COLUMN_NAMES from 
(TABLE_THOSE_COLUMNS_COME_FROM left join SECOND_TABLE_JOINING_WITH on 
(TABLE1.JOIN_CONDITION1=TABLE2.JOIN_CONDITION1 and
TABLE1.JOIN_CONDITION2=TABLE1.JOIN_CONDITION2)) where
BOOLEAN_CONDITIONS_FOR_PULL;"


#########################################################
# Part 4: disconnect from the database  
#########################################################
#when you are done interacting with the database, disconnect from it 
# the data that you pulled in from the database will remain in your environment.  
dbDisconnect(con)



#########################################################
# Part 5: Missingness for the DIM_CLIENT table 
#########################################################
# Missingness 
# the health records contain different values to refer to the same thing 
# there are two main types of missingness in the DIM_CLIENT table, which may be informative
# not asked: the client was never asked the question 
# no answer: the client was asked the question but did not want to answer 
# these mappings may be useful for data cleaning 
MISSINGNESS_CODES <- c("Unknown"="NotAsked", "None Selected"="NotAsked",
                       " " ="NotAsked","<description pending>"="NotAsked",
                       "<text>"="NotAsked", "Too young for primary completion"="NotAsked",
                       "Do not want to answer"="NoAnswer", "Do not know"="NoAnswer",
                       "Prefer not to answer"="NoAnswer",	"Undefined"="NoAnswer")

# note: 'too young for primary completion' is from the education table 
# since the data are for 18+ clients, we know that is outdated info 
# this is also a flag that some of the data in this table may be out of date 
# there are not date stamps associated with DIM_CLIENT entries in the same way they are for events (e.g. icd-10 and encode-fm entries)



