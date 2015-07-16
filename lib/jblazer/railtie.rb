require 'action_dispatch/http/mime_type'

module Jblazer
  class TemplateHandler
    def default_format
      Mime::JSON
    end

    def call template
      "json = Jblazer::Template.new(self); #{template.source} \n json.to_s"
    end
  end

  class Railtie < ::Rails::Railtie
    initializer :jblazer do |app|
      ActiveSupport.on_load :action_view do
        ActionView::Template.register_template_handler :jblazer, Jblazer::TemplateHandler.new
      end
    end

    def self.override_jbuilder!
      ActionView::Template.register_template_handler :jbuilder, Jblazer::TemplateHandler.new
    end
  end
end
