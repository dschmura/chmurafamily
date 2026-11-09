# frozen_string_literal: true

module Clientside
  module Projects
    class ResourcesController < Clientside::BaseController
      before_action :set_client_project
      before_action :ensure_clientside_enabled
      before_action :set_resource

      def show
      end

      private

      def set_resource
        @resource = @project.client_visible_resources.find_by(id: params[:id])
        return if @resource
        redirect_to clientside_project_path(@project), alert: t("clientside.area.resource_unavailable")
      end
    end
  end
end
