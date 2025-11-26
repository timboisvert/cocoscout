class AddDirectoryIndexes < ActiveRecord::Migration[8.1]
  def change
    # People indexes for directory performance
    add_index :people, :name, if_not_exists: true
    add_index :people, :email, if_not_exists: true
    add_index :people, :created_at, if_not_exists: true

    # Groups indexes for directory performance
    add_index :groups, :name, if_not_exists: true
    add_index :groups, :created_at, if_not_exists: true

    # Talent pool memberships - improve polymorphic lookups
    add_index :talent_pool_memberships, [ :member_type, :member_id, :talent_pool_id ],
              name: "index_tpm_on_member_and_pool", if_not_exists: true

    # Audition requests - improve polymorphic lookups
    add_index :audition_requests, [ :requestable_type, :requestable_id, :created_at ],
              name: "index_ar_on_requestable_and_created", if_not_exists: true
  end
end
