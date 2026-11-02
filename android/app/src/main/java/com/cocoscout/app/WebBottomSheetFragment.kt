package com.cocoscout.app

import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebBottomSheetFragment

/**
 * A page that slides up from the bottom as a sheet (the organization menu),
 * chosen by the path configuration's uri. Like iOS's medium modal_style.
 */
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web/modal/sheet")
class WebBottomSheetFragment : HotwireWebBottomSheetFragment()
