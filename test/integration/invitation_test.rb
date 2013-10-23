require 'test_helper'
require 'integration_tests_helper'

class InvitationTest < ActionDispatch::IntegrationTest
  def teardown
    Capybara.reset_sessions!
  end

  def send_invitation(url = new_user_invitation_path, &block)
    visit url

    fill_in 'user_email', :with => 'user@test.com'
    yield if block_given?
    click_button 'Send an invitation'
  end

  def set_password(options={}, &block)
    unless options[:visit] == false
      visit accept_user_invitation_path(:invitation_token => options[:invitation_token])
    end

    fill_in 'user_password', :with => '987654321'
    fill_in 'user_password_confirmation', :with => '987654321'
    yield if block_given?
    click_button options[:button] || 'Set my password'
  end

  test 'not authenticated user should be able to send a free invitation' do
    send_invitation new_free_invitation_path
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
  end

  test 'not authenticated user should not be able to send an invitation' do
    get new_user_invitation_path
    assert_redirected_to new_user_session_path
  end

  test 'authenticated user should be able to send an invitation' do
    sign_in_as_user

    send_invitation
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
  end

  test 'authenticated user with existing email should receive an error message' do
    user = create_full_user
    sign_in_as_user(user)
    send_invitation do
      fill_in 'user_email', :with => user.email
    end

    assert_equal user_invitation_path, current_path
    assert page.has_css?("input[type=text][value='#{user.email}']")
    assert page.has_css?('#error_explanation li', :text => 'Email has already been taken')
  end

  test 'authenticated user should not be able to visit edit invitation page' do
    sign_in_as_user

    visit accept_user_invitation_path

    assert_equal root_path, current_path
  end

  test 'not authenticated user with invalid invitation token should not be able to set his password' do
    user = User.invite!(:email => "valid@email.com")
    user.accept_invitation!
    visit accept_user_invitation_path(:invitation_token => 'invalid_token')

    assert_equal root_path, current_path
    assert page.has_css?('p#alert', :text => 'The invitation token provided is not valid!')
  end

  test 'not authenticated user with valid invitation token but invalid password should not be able to set his password' do
    user = User.invite!(:email => "valid@email.com")
    set_password :invitation_token => Thread.current[:token] do
      fill_in 'Password confirmation', :with => 'other_password'
    end
    assert_equal user_invitation_path, current_path
    assert page.has_css?('#error_explanation li', :text => /Password .*doesn\'t match/)
    assert_blank user.encrypted_password
  end

  test 'not authenticated user with valid data should be able to change his password' do
    user = User.invite!(:email => "valid@email.com")
    set_password :invitation_token => Thread.current[:token]

    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'Your password was set successfully. You are now signed in.')
    assert user.reload.valid_password?('987654321')
  end

  test 'after entering invalid data user should still be able to set his password' do
    user = User.invite!(:email => "valid@email.com")
    set_password :invitation_token => Thread.current[:token] do
      fill_in 'Password confirmation', :with => 'other_password'
    end
    assert_equal user_invitation_path, current_path
    assert page.has_css?('#error_explanation')
    assert_blank user.encrypted_password

    set_password :visit => false
    assert page.has_css?('p#notice', :text => 'Your password was set successfully. You are now signed in.')
    assert user.reload.valid_password?('987654321')
  end

  test 'sign in user automatically after setting it\'s password' do
    user = User.invite!(:email => "valid@email.com")
    set_password :invitation_token => Thread.current[:token]
    assert_equal root_path, current_path
  end

  test 'clear token and set invitation_accepted_at after recover password instead of accept_invitation' do
    user = User.invite!(:email => "valid@email.com")

    visit new_user_password_path
    fill_in 'user_email', :with => 'valid@email.com'
    click_button 'Send me reset password instructions'

    visit edit_user_password_path(:reset_password_token => Thread.current[:token])
    set_password :visit => false, :button => 'Change my password'

    user.reload
    # see https://github.com/dblock/devise_invitable/commit/906ea2eca4777eeb3a21dea4989350d2cb0c1d00
    # in our world users in this state aren't joined, they should not gain access to the site in this case
    assert_not_nil user.invitation_token
    assert_nil user.invitation_accepted_at
  end

  test 'user with invites left should be able to send an invitation' do
    User.stubs(:invitation_limit).returns(1)

    user = create_full_user
    user.invitation_limit = 1
    user.save!
    sign_in_as_user(user)

    assert_difference 'User.count' do
      send_invitation
    end
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
    user = User.find(user.id)

    # because there're now multiple inviters, the invitation limits are counted outside of devise_invitable
    # assert !user.has_invitations_left?
  end

  test 'user with no invites left should not be able to send an invitation' do
    User.stubs(:invitation_limit).returns(1)

    user = create_full_user
    user.invitation_limit = 0
    user.save!
    sign_in_as_user(user)

    assert_no_difference 'User.count' do
      send_invitation
    end
    assert_equal user_invitation_path, current_path
    assert page.has_css?('p#alert', :text => 'No invitations remaining')
  end

  test 'user with nil invitation_limit should default to User.invitation_limit' do
    User.stubs(:invitation_limit).returns(3)

    user = create_full_user
    assert_nil user[:invitation_limit]
    assert_equal 3, user.invitation_limit
    sign_in_as_user(user)

    send_invitation
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
    user = User.find(user.id)
    # we no longer decrement and count limits in devise_invitable (was assert_equal 2, user.invitation_limit)
    assert_equal 3, user.invitation_limit
  end

  test 'should not decrement invitation limit when trying to invite again a user which is invited' do
    User.stubs(:invitation_limit).returns(3)

    user = create_full_user
    assert_nil user[:invitation_limit]
    assert_equal 3, user.invitation_limit
    sign_in_as_user(user)

    send_invitation
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
    user = User.find(user.id)
    # we no longer decrement and count limits in devise_invitable (was assert_equal 2, user.invitation_limit)
    assert_equal 3, user.invitation_limit

    send_invitation
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
    user = User.find(user.id)
    # we no longer decrement and count limits in devise_invitable (was assert_equal 2, user.invitation_limit)
    assert_equal 3, user.invitation_limit
  end

  test 'authenticated user should not be able to send an admin invitation' do
    sign_in_as_user

    get new_admin_path
    assert_redirected_to new_admin_session_path
  end

  test 'authenticated admin should be able to send an admin invitation' do
    sign_in_as_user Admin.create(:email => 'admin@test.com', :password => '123456', :password_confirmation => '123456')

    send_invitation new_admin_path
    assert_equal root_path, current_path
    assert page.has_css?('p#notice', :text => 'An invitation email has been sent to user@test.com.')
  end
end
