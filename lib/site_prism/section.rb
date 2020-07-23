# frozen_string_literal: true

module SitePrism
  class Section
    include Capybara::DSL
    include ElementChecker
    include Loadable
    include DSL
    extend Forwardable

    attr_reader :root_element, :parent

    def self.set_default_search_arguments(*args)
      @default_search_arguments = args
    end

    def self.default_search_arguments
      @default_search_arguments ||
        (
          superclass.respond_to?(:default_search_arguments) &&
          superclass.default_search_arguments
        ) ||
        nil
    end

    def initialize(parent, root_element, &block)
      @parent = parent
      @root_element = root_element
      within(&block) if block_given?
    end

    def within
      Capybara.within(@root_element) { yield(self) }
    end

    # Capybara::DSL module "delegates" Capybara methods to the "page" method
    # as such we need to overload this method so that the correct scoping
    # occurs and calls within a section (For example section.find(element))
    # correctly scope to look within the section only
    def page
      return root_element if root_element

      SitePrism.logger.warn('Root Element not found; Falling back to `super`')
      super
    end

    def visible?
      page.visible?
    end

    def_delegators :capybara_session,
                   :execute_script,
                   :evaluate_script,
                   :within_frame

    def capybara_session
      Capybara.current_session
    end

    def parent_page
      candidate = parent
      candidate = candidate.parent until candidate.is_a?(SitePrism::Page)
      candidate
    end

    def native
      root_element.native
    end
  end
end
