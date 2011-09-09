# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20110909194842) do
  create_table "cities", :force => true do |t|
    t.string  "name",         :limit => 35, :default => "", :null => false
    t.string  "country_code", :limit => 3,  :default => "", :null => false
    t.string  "district",     :limit => 20, :default => "", :null => false
    t.integer "population",                 :default => 0,  :null => false
    t.integer "country_id"
  end

  create_table "countries", :force => true do |t|
    t.string  "code",                   :limit => 3,  :default => "",     :null => false
    t.string  "name",                   :limit => 52, :default => "",     :null => false
    t.string  "continent",              :limit => 0,  :default => "Asia", :null => false
    t.string  "region",                 :limit => 26, :default => "",     :null => false
    t.float   "surface_area",           :limit => 10, :default => 0.0,    :null => false
    t.integer "year_of_independence",   :limit => 2
    t.integer "population",                           :default => 0,      :null => false
    t.float   "life_expectancy",        :limit => 3
    t.float   "gross_national_product", :limit => 10
    t.float   "gnp_old",                :limit => 10
    t.string  "local_name",             :limit => 45, :default => "",     :null => false
    t.string  "government_form",        :limit => 45, :default => "",     :null => false
    t.string  "head_of_state",          :limit => 60
    t.integer "capital"
    t.string  "code2",                  :limit => 2,  :default => "",     :null => false
  end

  create_table "languages", :force => true do |t|
    t.integer "country_id"
    t.string  "country_code", :limit => 3,  :default => "",  :null => false
    t.string  "language",     :limit => 30, :default => "",  :null => false
    t.string  "official",     :limit => 0,  :default => "F", :null => false
    t.float   "percentage",   :limit => 4,  :default => 0.0, :null => false
  end
end
