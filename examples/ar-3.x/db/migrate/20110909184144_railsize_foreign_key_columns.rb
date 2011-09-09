class City < ActiveRecord::Base
end
class Country < ActiveRecord::Base
  set_primary_key 'code'
end

class RailsizeForeignKeyColumns < ActiveRecord::Migration
  def up
    rename_column 'cities', 'ID', 'id'
    rename_column 'countries', 'Code', 'code'
    add_column 'countries', 'id', :integer
    add_column 'cities', 'country_id', :integer

    count = 0
    Country.all.each do |record|
      count += 1
      record.update_attribute :id, count
    end
  end

  def down
  end
end
