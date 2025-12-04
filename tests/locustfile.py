from locust import FastHttpUser, TaskSet, task, between
import random

# Sample queries to test
QUERIES = [
    "Electronics", "Books", "Home", "Clothing",
    "Sports", "Toys", "Beauty", "Garden",
    "Automotive", "Health", "Alpha", "Beta",
    "Gamma", "Delta", "Epsilon", "Zeta",
    "Sigma", "Omega"
]

class UserBehavior(TaskSet):
    @task
    def search_products(self):
        query = random.choice(QUERIES)
        self.client.get(f"/products/search?q={query}", name="/products/search")

class WebsiteUser(FastHttpUser):
    tasks = [UserBehavior]
    wait_time = between(0, 0)
