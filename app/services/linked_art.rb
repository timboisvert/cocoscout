# frozen_string_literal: true

# Whose poster, wide image and description a ticket page shows when the
# show is the contractor's and another organization sells it under a
# connected contract (ContractConnection; Tim, 2026-11-14: the show is the
# contractor's, so how it looks and reads is theirs, and it flows to the
# organization that sells the tickets).
#
# Read through, never copied: the selling organization's own images and
# description stay where they are, as the fallback whenever the
# contractor's production has none, when it chooses "use our own" on the
# contract, and from the moment either side unlinks. An image or a
# description the selling organization set on one date, or on its
# ticketing setup, still wins there.
class LinkedArt
  # The contractor's production whose art stands in for this production's
  # on its ticket pages, or nil.
  def self.source_for(production)
    return nil unless production

    ContractConnection.connected.where(use_own_images: false, organization_id: production.organization_id)
                      .where(contract_id: Contract.where(production_id: production.id).select(:id))
                      .where.not(linked_production_id: nil)
                      .includes(:linked_production).order(:answered_at).first&.linked_production
  end

  # The same, for one date: the contract that booked it, when that one is
  # connected; else the production's.
  def self.source_for_show(show)
    return nil unless show&.production

    contract_id = show.space_rental_id && SpaceRental.where(id: show.space_rental_id).pick(:contract_id)
    if contract_id
      connection = ContractConnection.connected.where(use_own_images: false, contract_id: contract_id)
                                     .where.not(linked_production_id: nil).includes(:linked_production).first
      return connection.linked_production if connection
    end
    source_for(show.production)
  end

  # What a connection's contractor has for the ticket page to use, in words:
  # "a poster and a wide image", or nil when there's nothing yet.
  def self.offered_words(connection)
    theirs = connection.linked_production
    return nil unless theirs

    parts = [ ("a poster" if theirs.primary_poster&.image&.attached?), ("a wide image" if theirs.wide_image.attached?),
              ("a description" if theirs.description.present?) ].compact
    parts.to_sentence.presence
  end
end
