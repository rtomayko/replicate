class CreateWorldSchema < ActiveRecord::Migration
  def up
    rename_table 'City', 'cities'
    rename_column 'cities', "Name", 'name'
    rename_column 'cities', "CountryCode", 'country_code'
    rename_column 'cities', "District", 'district'
    rename_column 'cities', "Population", 'population'

    rename_table 'Country', 'countries'
    rename_column 'countries', "Name", 'name'
    rename_column 'countries', "Continent", 'continent'
    rename_column 'countries', "Region", 'region'
    rename_column 'countries', "SurfaceArea", 'surface_area'
    rename_column 'countries', "IndepYear", 'year_of_independence'
    rename_column 'countries', "Population", 'population'
    rename_column 'countries', "LifeExpectancy", 'life_expectancy'
    rename_column 'countries', "GNP", 'gross_national_product'
    rename_column 'countries', "GNPOld", 'gnp_old'
    rename_column 'countries', "LocalName", 'local_name'
    rename_column 'countries', "GovernmentForm", 'government_form'
    rename_column 'countries', "HeadOfState", 'head_of_state'
    rename_column 'countries', "Capital", 'capital'
    rename_column 'countries', "Code2", 'code2'

    rename_table 'CountryLanguage', 'countries_languages'
    rename_column 'countries_languages', "CountryCode", 'country_code'
    rename_column 'countries_languages', "Language", 'language'
    rename_column 'countries_languages', "IsOfficial", 'official'
    rename_column 'countries_languages', "Percentage", 'percentage'
  end

  def down
  end
end
