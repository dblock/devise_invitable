class User < ActiveRecord::Base
  devise :database_authenticatable, :registerable, :validatable, :confirmable, :invitable
  
  attr_accessible :email, :username, :password, :password_confirmation
  
  validates :username, :length => { :maximum => 20 }
end
