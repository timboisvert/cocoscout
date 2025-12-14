# frozen_string_literal: true

class RoleVacancyShow < ApplicationRecord
  belongs_to :role_vacancy
  belongs_to :show
end
