require 'test_helper'
require 'model_tests_helper'

class Devise::RegistrationsControllerTest < ActionController::TestCase
  def setup
    @issuer = new_user#users(:issuer)
    @issuer.valid?
    assert @issuer.valid?, 'starting with a valid user record'

    # josevalim: you are required to do that because the routes sets this kind
    # of stuff automatically. But functional tests are not using the routes.
    # see https://github.com/plataformatec/devise/issues/1196
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  test "invited users may still sign up directly by themselves" do
    # invite the invitee
    sign_in @issuer
    invitee_email = "invitee@example.org"

    User.invite!(:email => invitee_email) do |u|
      u.skip_invitation = true
    end
    sign_out @issuer

    @invitee = User.where(:email => invitee_email).first
    assert_blank @invitee.encrypted_password, "the password should be unset"

    # sign_up the invitee
    post :create, :user => {:email => invitee_email, :password => "1password"}

    @invitee = User.where(:email => invitee_email).first
    assert_present @invitee.encrypted_password
    assert_nil @invitee.invitation_accepted_at
    assert_nil @invitee.invitation_token
  end

  test "not invitable resources can register" do
    @request.env["devise.mapping"] = Devise.mappings[:admin]
    invitee_email = "invitee@example.org"

    post :create, :admin => {:email => invitee_email, :password => "1password"}

    @invitee = Admin.where(:email => invitee_email).first
    assert_present @invitee.encrypted_password
  end
end
