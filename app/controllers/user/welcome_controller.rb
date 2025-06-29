class User::WelcomeController < UserApplicationController
  def index
    @top_products = ProductsRecommendation.filter_products_with_aggregation(current_user, 3, 0)
    @top_posts = top_posts
    @food_fact = Recipe.desc(:created_at).first

    if @food_fact.nil? || @food_fact.created_at < 30.minutes.ago
      # @food_fact = RandomFacts.random_recipe
      if @food_fact&.instructions.blank?
        offset = rand(Recipe.count)
        @food_fact = Recipe.skip(offset).first
        return
      end
      @food_fact.save
    end

    if current_user.present?
      @user_nutritional_data = current_user.get_nutritional_stats
      
      midnight = Time.current.end_of_day

      cookies[:nutritional_completeness_ratio] = { value: current_user.compute_nutritional_goal, expires: midnight }
    end

    @most_experienced_users = User.most_experienced.limit(5)
    @today_goal = { title: current_user.goal_title, description: current_user.goal_description, target: current_user.goal_target, progress: current_user.goal_progress} if current_user.goal_created_at.present? && current_user.goal_created_at.to_date == Time.now.to_date
    puts @today_goal
  end

  def contact
    FeedbackMessage.create(params.permit(:email, :name, :message))
    respond_to do |format|
      format.json { render json: { message: 'Feedback sent!' }, status: :ok }
      format.html { redirect_to '/', notice: 'Feedback sent!' }
    end
  end

  def search
    if params[:query].blank?
      @products = []
      @users = []
      @posts = []
      return
    end
    @products = Product.where(name: /#{params[:query]}/i).limit(5).to_a
    @users = User.or({ first_name: /#{params[:query]}/i }, { last_name: /#{params[:query]}/i }).limit(5).to_a
    @posts = Post.where(:hashtags.in => [params[:query]]).top_level.limit(5).to_a
  end

  def recommended_products
    if current_user.present?
      recommendation_data = RecommendationsApi.paginated_products(current_user, 1, 3)
      recommended_products = Product.where(:_id.in => recommendation_data["products"])
    else
      recommended_products = []
    end
    
    return if recommended_products.blank?
    
    render partial: 'recommended_products', locals: { recommended_products: recommended_products }
  end

  def add_goal
    current_user.update_attribute(:goal_title, params[:goal_title])
    current_user.update_attribute(:goal_description, params[:goal_description])
    current_user.update_attribute(:goal_created_at, Time.now)
    current_user.update_attribute(:goal_progress, 0)
    current_user.update_attribute(:goal_target, params[:goal_target])
    current_user.save
    redirect_to user_root_path
  end

  def update_goal
    current_user.update_attribute(:goal_progress, params[:goal_progress])
    current_user.save
    redirect_to user_root_path
  end

private

  def top_posts
    pipeline = [
      {
        '$lookup' => {
          'from' => 'ratings',
          'localField' => '_id',
          'foreignField' => 'post_id',
          'as' => 'ratingDetails'
        }
      },
      {
        '$project' => {
          'title' => 1,
          'content' => 1,
          'up_number' => {
            '$size' => {
              '$filter' => {
                'input' => '$ratingDetails',
                'as' => 'rating',
                'cond' => { '$eq' => ['$$rating.vote', 'up_vote'] }
              }
            }
          },
          'down_number' => {
            '$size' => {
              '$filter' => {
                'input' => '$ratingDetails',
                'as' => 'rating',
                'cond' => { '$eq' => ['$$rating.vote', 'down_vote'] }
              }
            }
          }
        }
      },
      {
        '$lookup' => {
          'from' => 'posts',
          'localField' => '_id',
          'foreignField' => 'response_to',
          'as' => 'replies'
        }
      },
      {
        '$addFields' => {
          'replies_number' => { '$size' => '$replies' }
        }
      },
      {
        '$addFields' => {
          'overall_ratings' => { '$add' => ['$up_number', '$down_number'] }
        }
      },
      { '$sort' => { 'overall_ratings' => -1 } },
      { '$limit' => 3 }
    ]

    Post.collection.aggregate(pipeline).to_a
  end
end
