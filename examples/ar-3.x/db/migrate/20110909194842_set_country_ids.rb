class Country < ActiveRecord::Base
end

class SetCountryIds < ActiveRecord::Migration
  def up
    count = 0
    Country.all.each do |record|
      count += 1
      execute "UPDATE countries SET id = #{count} WHERE code = '#{record.code}'"
    end

    execute "UPDATE cities SET country_id = (SELECT countries.id FROM countries WHERE countries.code = cities.country_code)"
    execute "UPDATE languages SET country_id = (SELECT countries.id FROM countries WHERE countries.code = languages.country_code)"

    execute "ALTER TABLE countries DROP PRIMARY KEY"
    execute "ALTER TABLE countries ADD PRIMARY KEY (id)"
    execute "ALTER TABLE countries MODIFY id int(11) NOT NULL AUTO_INCREMENT"
  end

  def down
  end
end
