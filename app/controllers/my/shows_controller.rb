class My::ShowsController < ApplicationController
  def index
    @productions = Production.joins(casts: [ :casts_people ]).where(casts_people: { person_id: Current.user.person.id }).distinct
  end
end
