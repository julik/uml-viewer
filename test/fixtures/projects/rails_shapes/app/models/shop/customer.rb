class Shop::Customer < ApplicationRecord
  belongs_to :store

  def home = Store.first
end
