require 'http'
require 'erb'
require 'json'

class OpenFoodFacts
  @@API_V3 = 'https://world.openfoodfacts.org/api/v3'.freeze
  @@API_V2 = 'https://world.openfoodfacts.org/api/v2'.freeze

  def self.product(ean)
    begin
      product = get(@@API_V3, "/product/#{ean}")["product"]
    rescue
      return nil
    end

    return nil if product.nil? || product.empty?
    map_product_to_model(product)
  end

  def self.search_by_name(name)
    query = "search_terms=#{ERB::Util.url_encode(name)}&json=1&page_size=1&fields=code"
    response = get("https://world.openfoodfacts.org/cgi/search.pl?", query)
    return nil if response["products"].nil? || response["products"].empty?

    product(response["products"][0]["code"])
  end

  def self.search_by_name_list(name, limit, page)
    query = "search_terms=#{ERB::Util.url_encode(name)}&json=1&page_size=#{limit}&page=#{page}&fields=code,product_name"
    response = get("https://world.openfoodfacts.org/cgi/search.pl?", query)
    return nil if response["products"].nil?

    {
      products: response["products"].map { |product| map_product_to_model(product) },
      total: (response["count"].to_i / limit.to_f).ceil
    }
  end

  def self.get(api, query)
    res = HTTP.get(api + query)
    return nil unless res.status.success?
    JSON.parse(res.body.to_s)
  end

  private

  def self.map_product_to_model(product)
    allergens = product["allergens_tags"]&.select { |a| a.start_with?('en:') } || []
    ingredients = product["ingredients_tags"]&.select { |i| i.start_with?('en:') } || []
    vegan = !(product["ingredients_analysis_tags"] || []).include?("en:non-vegan")
    vegetarian = !(product["ingredients_analysis_tags"] || []).include?("en:non-vegetarian")

    Product.new(
      ean: product["_id"] || product["code"],
      brand: product["brands"].to_s.presence || 'Unknown',
      name: product["product_name"].to_s.presence || 'Unknown',
      nutriscore: product["nutrition_grades"],
      allergens: allergens,
      ingredients: ingredients,
      weight: product["product_quantity"],
      calories: product.dig("nutriments", "energy-kcal_100g")&.to_f&.round(2),
      protein: product.dig("nutriments", "proteins_100g")&.to_f&.round(2),
      fat: product.dig("nutriments", "fat_100g")&.to_f&.round(2),
      saturated_fat: product.dig("nutriments", "saturated-fat_100g")&.to_f&.round(2),
      carbohydrates: product.dig("nutriments", "carbohydrates_100g")&.to_f&.round(2),
      fiber: product.dig("nutriments", "fiber_100g")&.to_f&.round(2),
      sugar: product.dig("nutriments", "sugars_100g")&.to_f&.round(2),
      sodium: product.dig("nutriments", "sodium_100g")&.to_f&.round(2),
      vegan: vegan,
      vegetarian: vegetarian,
      image_url: product["image_url"]
    )
  end
end
