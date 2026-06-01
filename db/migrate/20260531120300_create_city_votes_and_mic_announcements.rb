# frozen_string_literal: true

# Two new tables:
#  * city_votes — anyone votes for cities they want the finder in next.
#  * mic_announcements — producer posts a news item on the mic page that
#    optionally pushes to subscribers.
class CreateCityVotesAndMicAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :city_votes do |t|
      t.string :city, null: false
      t.string :state, null: false
      t.bigint :user_id          # set if signed-in
      t.string :email            # set if not signed-in
      t.timestamps
    end
    add_index :city_votes, %i[city state]
    add_index :city_votes, :user_id
    # Don't let the same signed-in user vote twice for the same city.
    add_index :city_votes, %i[user_id city state], unique: true,
              where: "user_id IS NOT NULL"

    create_table :mic_announcements do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :posted_by_user_id, null: false
      t.string :title
      t.text :body, null: false
      t.boolean :notify_subscribers, null: false, default: false
      t.datetime :posted_at, null: false
      t.timestamps
    end
    add_index :mic_announcements, %i[mic_id posted_at]
  end
end
