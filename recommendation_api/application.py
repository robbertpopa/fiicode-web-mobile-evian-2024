import os
import threading
import time
import schedule
from pymongo.collection import Collection

from flask import Flask, request, url_for, jsonify
from flask_pymongo import PyMongo
from pymongo.errors import DuplicateKeyError

from model import Product, UserForum
from objectid import PydanticObjectId

from product_recommender import recommend_products

from posts_embeddings import update_embeddings
from posts_recommender import recommend_posts

app = Flask(__name__)
app.config["MONGO_URI"] = "mongodb://localhost:27017/freshly"
pymongo = PyMongo(app)

products: Collection = pymongo.db.products
users: Collection = pymongo.db.users

posts: Collection = pymongo.db.posts
embeddings: Collection = pymongo.db.embeddings
ratings: Collection = pymongo.db.ratings


def run_in_background(interval=1):
    cease_continuous_run = threading.Event()

    class ScheduleThread(threading.Thread):
        @classmethod
        def run(cls):
            while not cease_continuous_run.is_set():
                schedule.run_pending()
                time.sleep(interval)

    continuous_thread = ScheduleThread()
    continuous_thread.start()
    return cease_continuous_run


def update_embeddings_job():
    update_embeddings(embeddings, posts)


schedule.every().day.at("00:00").do(update_embeddings_job)

run_in_background()


@app.errorhandler(404)
def resource_not_found(e):
    return jsonify(error=str(e)), 404


@app.errorhandler(DuplicateKeyError)
def resource_not_found(e):
    return jsonify(error=f"Duplicate key error."), 400


@app.route("/products/<string:user_id>", methods=["GET"])
def list_products(user_id):
    user = users.find_one_or_404({"_id": PydanticObjectId(user_id)})
    user_allergens = user.get("allergens_ids", []) or []
    user_basket_ids = user.get("favorites", []) or []
    user_dietary_preferences = user.get("dietary_preferences") or "NONE"

    all_products = [Product(**doc) for doc in products.find()]
    user_basket = [product for product in all_products if product.id in user_basket_ids]

    top_recommendations = recommend_products(user_basket, all_products, user_allergens, user_dietary_preferences)
  
    return {
        "products": [product.id.to_json() for product in top_recommendations],
    }


@app.route("/products/page/<int:page>/<string:user_id>", methods=["GET"])
def list_products_page(page, user_id):
    user = users.find_one_or_404({"_id": PydanticObjectId(user_id)})
    user_allergens = user.get("allergens_ids", []) or []
    user_basket_ids = user.get("favorites", []) or []
    user_dietary_preferences = user.get("dietary_preferences") or "NONE"

    all_products = [Product(**doc) for doc in products.find({"status": "APPROVED"})]
    user_basket = [product for product in all_products if product.id in user_basket_ids]

    per_page = request.args.get("per_page", 10, type=int)

    top_recommendations = recommend_products(user_basket, all_products, user_allergens, user_dietary_preferences, len(all_products))
    total_pages = (len(top_recommendations) + per_page - 1) // per_page

    start_index = per_page * (page - 1)
    end_index = min(start_index + per_page, len(top_recommendations))

    recommendations_for_page = top_recommendations[start_index:end_index]

    return {
        "products": [product.id.to_json() for product in recommendations_for_page],
        "total_pages": total_pages,
    }


@app.route("/posts/<string:user_id>", methods=["GET"])
def list_posts(user_id):
    user = users.find_one_or_404({"_id": PydanticObjectId(user_id)})
    current_user_forum = UserForum(_id=user["_id"], following_ids=user["following_ids"])

    liked_posts = []
    disliked_posts = []

    for doc in ratings.find({"user_id": current_user_forum.id, "vote": {"$in": ["up_vote", "down_vote"]}}):
        if doc["vote"] == "up_vote":
            liked_posts.append(doc["post_id"])
        elif doc["vote"] == "down_vote":
            disliked_posts.append(doc["post_id"])

    top_recommendations = recommend_posts(
        liked_posts, disliked_posts, current_user_forum.following_ids, embeddings
    )

    return {
        "posts": [post.id.to_json() for post in top_recommendations],
    }


@app.route("/posts/page/<int:page>/<string:user_id>", methods=["GET"])
def list_posts_page(page, user_id):
    user = users.find_one_or_404({"_id": PydanticObjectId(user_id)})
    current_user_forum = UserForum(_id=user["_id"], following_ids=user["following_ids"])

    liked_posts = []
    disliked_posts = []

    for doc in ratings.find({"user_id": current_user_forum.id, "vote": {"$in": ["up_vote", "down_vote"]}}):
        if doc["vote"] == "up_vote":
            liked_posts.append(doc["post_id"])
        elif doc["vote"] == "down_vote":
            disliked_posts.append(doc["post_id"])

    per_page = request.args.get("per_page", 10, type=int)

    top_recommendations = recommend_posts(
        liked_posts, disliked_posts, current_user_forum.following_ids, embeddings
    )

    start_index = per_page * (page - 1)
    end_index = min(start_index + per_page, len(top_recommendations))

    recommendations_for_page = top_recommendations[start_index:end_index]

    total_pages = (len(top_recommendations) + per_page - 1) // per_page

    return {
        "posts": [post.id.to_json() for post in recommendations_for_page],
        "total_pages": total_pages,
    }
