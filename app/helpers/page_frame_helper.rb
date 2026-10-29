module PageFrameHelper
  # The page's own content in the application and native layouts. A link or
  # GET form that stays on this page and only changes its query loads into
  # this frame instead of loading the whole page (page_frame_controller.js):
  # the navigation and the scroll stay put and the app stays on the same
  # screen. Links that go anywhere else still load the whole page (_top).
  def page_frame_tag(&block)
    turbo_frame_tag "page", target: "_top", class: "block",
      data: { controller: "page-frame",
              action: "turbo:before-prefetch->page-frame#prefetching turbo:before-fetch-response->page-frame#fetched turbo:before-frame-render->page-frame#beforeRender turbo:frame-load->page-frame#loaded" },
      &block
  end
end
