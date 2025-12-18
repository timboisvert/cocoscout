class RemoveBadRoleEligibilitiesIndex < ActiveRecord::Migration[8.1]
  def change
    # The old index on (role_id, member_id) doesn't include member_type,
    # which breaks polymorphic uniqueness (Person#1 vs Group#1 would conflict)
    remove_index :role_eligibilities, [:role_id, :member_id], 
                 name: "index_role_eligibilities_on_role_id_and_member_id",
                 if_exists: true
  end
end
