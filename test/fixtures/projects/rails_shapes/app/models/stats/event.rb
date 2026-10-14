module Stats
  class Event < ApplicationRecord
    belongs_to :visit

    def last_visit = Visit.last
  end
end
