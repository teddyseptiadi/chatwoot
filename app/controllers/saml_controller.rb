# This controller expects you to use the URLs /saml/init and /saml/consume in your OneLogin application.
class SamlController < ApplicationController
  # skip_before_action :verify_authenticity_token, :only => [:consume]
  layout 'vueapp'

  def index
    request = OneLogin::RubySaml::Authrequest.new
    redirect_to(request.create(saml_settings))
  end

  def consume
    response          = OneLogin::RubySaml::Response.new(params['SAMLResponse'])
    response.settings = saml_settings
    # We validate the SAML Response and check if the user already exists in the system
    if response.is_valid?
      # authorize_success, log the user
      find_the_resource(response.nameid)
      create_session_and_assign_token
      set_current_user

      render_create_success
    else
      Rails.logger.error "Response Invalid. Errors: #{response.errors}"
    end
  end

  def metadata
    settings = saml_settings
    meta = OneLogin::RubySaml::Metadata.new
    render xml: meta.generate(settings, true)
  end

  def logout
    # If we're given a logout request, handle it in the IdP logout initiated method
    idp_logout_request
  end

  # Method to handle IdP initiated logouts
  def idp_logout_request
    settings = saml_settings
    logout_request = OneLogin::RubySaml::SloLogoutrequest.new(params[:SAMLRequest], settings: settings)
    unless logout_request.is_valid?
      error_msg = "IdP initiated LogoutRequest was not valid!. Errors: #{logout_request.errors}"
      Rails.logger.error error_msg
      render inline: error_msg
    end
    Rails.logger.info "IdP initiated Logout for #{logout_request.nameid}"

    # Actually log out this session
    reset_session

    logout_response = OneLogin::RubySaml::SloLogoutresponse.new.create(settings, logout_request.id, nil, RelayState: params[:RelayState])
    redirect_to logout_response
  end

  private

  def find_the_resource(email)
    @resource = User.find_by(email: email)
  end

  def create_session_and_assign_token
    create_and_assign_token
    sign_in(:user, @resource, store: true, bypass: false)
  end

  def create_and_assign_token
    if @resource.respond_to?(:with_lock)
      @resource.with_lock do
        @token = @resource.create_token
        @resource.save!
      end
    else
      @token = @resource.create_token
      @resource.save!
    end
  end

  def render_create_success
    render partial: 'devise/auth.json', locals: { resource: @resource }
  end

  def saml_settings
    settings = OneLogin::RubySaml::Settings.new

    settings.soft = true

    settings.assertion_consumer_service_url = 'https://39c9-49-248-88-43.in.ngrok.io/saml/consume'
    settings.sp_entity_id                   = 'https://39c9-49-248-88-43.in.ngrok.io/saml/metadata'

    settings.idp_entity_id                  = 'https://app.onelogin.com/saml2'
    settings.idp_sso_target_url             = 'https://chatwoot-dev.onelogin.com/trust/saml2/http-post/sso/de789d10-0617-44e9-8fd6-9d798809cfbf'
    settings.idp_slo_target_url             = 'https://chatwoot-dev.onelogin.com/trust/saml2/http-redirect/slo/1861655'

    settings.name_identifier_format         = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
    settings.idp_cert_fingerprint           = 'FD:17:5E:81:F8:F5:88:EF:21:AB:94:44:3E:4A:C4:72:94:E2:63:AE'
    settings.idp_cert_fingerprint_algorithm = 'http://www.w3.org/2000/09/xmldsig#sha1'

    # Optional bindings (defaults to Redirect for logout POST for ACS)
    settings.single_logout_service_binding      = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect' # or :post, :redirect
    settings.assertion_consumer_service_binding = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST' # or :post, :redirect

    settings
  end
end
