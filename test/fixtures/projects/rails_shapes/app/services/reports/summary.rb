module Reports
  class Summary
    STATUS_LABELS = { open: "Open" }.freeze

    def orders = Order.all
    def json = JSON.generate(STATUS_LABELS)
  end
end
