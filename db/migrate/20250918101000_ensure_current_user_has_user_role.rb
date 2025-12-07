# frozen_string_literal: true

class EnsureCurrentUserHasUserRole < ActiveRecord::Migration[7.0]
  def up
    # This migration is intended to be run manually after login if needed
    User.find_each do |user|
      user.production_companies.each do |company|
        unless UserRole.exists?(user: user, production_company: company)
          UserRole.create!(user: user, production_company: company, role: 'manager')
        end
      end
    end
  end

  def down
    # No-op
  end
end
