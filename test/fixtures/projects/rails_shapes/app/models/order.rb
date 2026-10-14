class Order < ApplicationRecord
  belongs_to :approved_by, class_name: "User", optional: true

  def labels = Reports::Summary::STATUS_LABELS.lazy
  def price = Pricing.new(self)
  def parse(text) = JSON.parse(text)
  def total = Order.sum(:amount)
end
