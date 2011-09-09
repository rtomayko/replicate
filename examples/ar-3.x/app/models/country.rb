class Country < ActiveRecord::Base
  has_many :cities
  has_many :languages

  replicate_associations :cities, :languages
end
