module Reports
  class Exporter
    def self.build = new
    private_class_method def self.secret = 1

    def run
      rows.map { |row| format(row) if row }
    end

    protected

    def rows = []

    private

    def format(row) = row.to_s
    def helper = nil
    public :helper

    class << self
      def defaults = {}

      private

      def hidden = nil
    end
  end
end
