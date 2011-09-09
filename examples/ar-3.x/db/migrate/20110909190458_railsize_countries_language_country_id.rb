class Language < ActiveRecord::Base
  set_primary_key :country_code
end
class Country < ActiveRecord::Base
end

class RailsizeCountriesLanguageCountryId < ActiveRecord::Migration
  def up
    rename_table 'countries_languages', 'languages'
    add_column 'languages', 'id', :integer
    add_column 'languages', 'country_id', :integer

    execute "ALTER TABLE languages DROP PRIMARY KEY"

    puts "languages = #{Language.count}"

    count = 0
    Language.all.each do |record|
      count += 1
      execute "
        UPDATE languages
           SET id = #{count}
         WHERE country_code = '#{record.country_code}'
           AND language = '#{record.language}'
      "
    end
    execute "ALTER TABLE languages ADD PRIMARY KEY (id)"
    execute "ALTER TABLE languages MODIFY id int(11) NOT NULL AUTO_INCREMENT"
  end

  def down
  end
end
