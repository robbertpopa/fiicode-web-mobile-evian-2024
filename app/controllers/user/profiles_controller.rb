class User::ProfilesController < UserApplicationController
  layout 'user_profile'
  before_action :authenticate_user!, except: %i[account]
  before_action :set_links

  def show
    render layout: 'user_application'
  end

  def user
    if request.put?
      update_user_profile
    end
  end

  def account
    if current_user.present?
      @login = current_user.login
    elsif params[:login].present? and params[:token].present?
      @login = Login.find(params[:login]) rescue not_found
    else
      redirect_to user_login_path and return;
    end

    @token = params[:token]
    if @token.present? and @login.reset_password_key != @token
      redirect_to user_login_path, alert: "Invalid or expired password reset token" and return
    end
    @allowed_update = (params[:token].present? and @login.reset_password_key == params[:token])

    if request.put?
      if params[:username].present? && params[:username] != @login.username
        begin
          @login.username = params[:username]
          @login.confirmed_username = true
          @login.save!
          redirect_to user_user_profile_path, notice: "Nickname updated", status: :see_other and return
        rescue Mongoid::Errors::Validations => e
          render json: { message: "Username is already used, try again!" }, status: :unauthorized and return
        end
      end

      if params[:password] != params[:password_confirmation]
        render json: { message: 'Password and password confirmation do not match' }, status: :bad_request and return
      end

      unless @allowed_update
        render json: { message: 'Invalid or expired password reset token' }, status: :unauthorized and return
      end

      @login.password = params[:password]
      @login.save!
      if current_user.present?
        redirect_to user_user_profile_path, notice: "Password updated", status: :see_other
      else
        redirect_to user_login_path, notice: "Password updated", status: :see_other
      end
    end
  end

  def dietary_preferences
    @dietary_preferences = User::DIETARY_PREFERENCES_VALUES

    if request.put?
      current_user.allergens_ids = params["allergens[]"]
      current_user.dietary_preferences = params[:dietary_preferences]
      current_user.save!

      render json: { message: 'Dietary preferences updated' }, status: :ok
    end
  end

  def notifications
    @notifications = current_user.notifications.newest_first
  end

  def billing
  end

  def get_plus
    if params[:price].present?
      x = BillingService::Plus.create_checkout_session(current_user, params[:price], billing_user_profile_url)
      redirect_to x[:url], allow_other_host: true
    end
  end

  def cancel_plus
    BillingService::Plus.cancel_subscription(current_user)
    redirect_to billing_user_profile_path, notice: "Subscription cancelled"
  end

  protected

  def set_links
    if current_user.present?
      @links = [{ href: user_user_profile_path, text: "Profile", icon: "account-outline", md: true },
                { href: account_user_profile_path, text: "Account", icon: "lock-outline", md: true },
                { href: dietary_preferences_user_profile_path, text: "Preferences", icon: "food-outline", md: true },
                { href: user_hub_user_path(current_user), text: "Hub page", icon: "forum-outline", md: false },
                { href: notifications_user_profile_path, text: "Notifications", icon: "bell-outline", md: true },
                { href: billing_user_profile_path, text: "Billing", icon: "currency-usd", md: true},
                { href: user_basket_path, text: "Basket", icon: "cart-outline", md: false}]
    else
      @links = []
    end
  end

  private

  def update_user_profile
    if params[:profile_picture].present? || params.dig(:user, :remove_profile_picture) == "true"
      current_user.update_attributes!(user_params.merge(profile_picture: profile_picture_param))
    else
      current_user.update_attributes!(user_params)
    end
    render status: :ok
  rescue
    render status: :unprocessable_entity
  end

  def user_params
    params.permit(:first_name, :last_name, :weight, :height, :city, :country)
  end

  def profile_picture_param
    params.dig(:user, :remove_profile_picture) == "true" ? nil : params[:profile_picture]
  end
end
