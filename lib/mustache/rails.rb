require 'action_view'
require 'active_support'
require 'mustache'

class Mustache

  # Subclass Mustache::Rails for your view files. You should place view files
  # in app/views/:controller/:action.rb. Mustache::Rails registers a
  # TemplateHandler for ".rb" files.
  class Rails < Mustache
    attr_accessor :view

    def method_missing(method, *args, &block)
      view.send(method, *args, &block)
    end

    def respond_to?(method, include_private=false)
      super(method, include_private) || view.respond_to?(method, include_private)
    end

    # Redefine where Mustache::Rails templates locate their partials: in the
    # same file as the current template file.
    def partial(name)
      File.read(File.join(self.class.template_file.dirname, "#{name}.#{Config.template_extension}"))
    end

    # You can change these defaults in, say, a Rails initializer or
    # environment.rb, e.g.:
    #
    # Mustache::Rails::Config.template_base_path = Rails.root.join('app', 'templates')
    module Config
      def self.template_base_path
        @template_base_path ||= ::Rails.root.join('app', 'templates')
      end

      def self.template_base_path=(value)
        @template_base_path = value
      end

      def self.template_extension
        @template_extension ||= 'html.mustache'
      end

      def self.template_extension=(value)
        @template_extension = value
      end
    end

    # This helper defines a view helper for rendering mustache templates from
    # other types of templates (Erb, Haml, etc.). This borrows from
    # ActionView's render_partial.
    module ViewHelper
      def render_stash(partial_path, local_assigns={})
        if partial_path.include?('/')
          path = File.join(File.dirname(partial_path), "#{File.basename(partial_path)}")
        elsif controller
          path = "#{controller.class.controller_path}/#{partial_path}"
        else
          path = "#{partial_path}"
        end
        self.view_paths.find_template(path, self.template_format).render(self, local_assigns)
      end
    end

    class TemplateHandler < ActionView::TemplateHandler

      def render(template, local_assigns, &block)
        mustache = mustache_class_from_template(template)
        # Should we allow users to set a custom template_path/template_file
        # for a Mustache::Rails subclass? If so, there needs to be a change to
        # Mustache::Rails.template_path and Mustache::Rails.template_file.
        mustache.template_file = Config.template_base_path + template.base_path + "#{template.name}.#{Config.template_extension}"
        returning mustache.new do |result|
          copy_instance_variables_to(result)
          result.view    = @view
          result[:yield] = @view.instance_variable_get(:@content_for_layout)
          result.context.update(local_assigns)
        end.to_html
      end

      private

      def copy_instance_variables_to(mustache)
        variables = @view.controller.instance_variable_names
        variables -= %w(@template)

        if @view.controller.respond_to?(:protected_instance_variables)
          variables -= @view.controller.protected_instance_variables
        end

        variables.each do |name|
          mustache.instance_variable_set(name, @view.controller.instance_variable_get(name))
        end

        # For an anonymous mustache, you probably want +attr_reader+ declared for
        # your instance variables. Otherwise there's no way you can access them on
        # the template.
        if mustache.class == Mustache
          mustache.class.class_eval do
            attr_reader *variables.map {|name| name.to_s.gsub(/^@/, "") }
          end
        end
      end

      def mustache_class_from_template(template)
        const_name = [template.base_path, template.name].compact.join("/").camelize
        defined?(const_name) ? const_name.constantize : Mustache
      end
    end
  end
end

::ActiveSupport::Dependencies.load_paths << Rails.root.join("app", "views")
::ActionView::Base.send(:include, Mustache::Rails::ViewHelper)
::ActionView::Template.register_template_handler(:rb, Mustache::Rails::TemplateHandler)
