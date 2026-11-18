# frozen_string_literal: true

# A role is its name and how many (Tim, 2026-11-18: "we used to do that, but
# now we use staffing to deal with techs. So I'd rather just the role, the
# number of them, that's it."). The Performing / Technical choice is gone
# from every screen, and Tim said the same day to rewrite the roles already
# marked Crew as plain roles, so nothing hidden treats them differently.
#
# Only the mark changes: the role, its slots, its position, its cast, and
# whether it's a show role in a lineup (roles.standing) all stay as they are.
# From here on, switching a production from roles to acts splits a
# multi-person role into acts whatever it used to be marked; a role that
# shouldn't be an act is made a show role in the lineup.
#
# Plain SQL, no app code. One way: which roles were Crew isn't kept anywhere,
# so `down` leaves them as plain roles.
class CrewRolesBecomePlainRoles < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE roles SET category = 'performing' WHERE category = 'technical'"
  end

  def down
    # Nothing to put back: the Crew mark isn't recorded anywhere else.
  end
end
