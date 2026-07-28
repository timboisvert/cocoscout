# frozen_string_literal: true

# How a contract's signature is handled:
#   offline — the classic path: it was signed elsewhere and (optionally) the
#             signed PDF is uploaded. Every existing/in-flight contract is this.
#   esign   — CocoScout hosts the signing: the contract is created here, sent for
#             an in-app e-signature, and the signed PDF is generated, not uploaded.
#
# Defaulting to "offline" so nothing about existing contracts changes; the native
# signing flow only engages when a new contract is explicitly created as :esign.
class AddSigningModeToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :signing_mode, :string, null: false, default: "offline"
  end
end
