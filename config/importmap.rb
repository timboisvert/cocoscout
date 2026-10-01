# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"
pin "chart.js", to: "chart.js" # @4.4.1 - ESM wrapper
pin "chart.umd.js", to: "chart.umd.js" # Chart.js UMD build
pin "@hotwired/hotwire-native-bridge", to: "@hotwired--hotwire-native-bridge.js" # @1.2.2
pin "leaflet", to: "https://unpkg.com/leaflet@1.9.4/dist/leaflet-src.esm.js"
# Door QR scanning; imported only when the camera starts (door_controller.js).
pin "qr-scanner", to: "https://cdn.jsdelivr.net/npm/qr-scanner@1.4.2/qr-scanner.min.js", preload: false
