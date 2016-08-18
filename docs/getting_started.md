# Getting Started


## Building our first application with Ray

Lets see how easy is build a blog (again? really? ¯\\_(ツ)_/¯) using **Ray**!

To do this, we will use the Peewee ORM, which Ray is absolutely compatible (as well with SQLAlchemy and Google App Engine).

So, lets install Peewee and Ray and the Ray plugin to integrated with the ORM.


```bash
pip install peewee
pip install ray_framework
pip install ray_peewee
```

After that, create an *app.py* file with our first model: Post.

```python
# app.py

import peewee
from ray_peewee.all import PeeweeModel
from ray.wsgi.wsgi import application
from ray.endpoint import endpoint


database = peewee.SqliteDatabase('example.db')


class DBModel(PeeweeModel):
    class Meta:
        database = database


@endpoint('/post')
class Post(DBModel):
    title = peewee.CharField()
    description = peewee.TextField()

```

Now, lets run our application and check if it's everything alright.
**If don't want to use curl, you can use the Postman app. [Just click here](https://www.getpostman.com/collections/46d9f79b0bc1a4df3909).**

```bash
ray up --wsgifile=app.py

# if you're using virtualenv
ray up --wsgifile=app.py --env <env_dir>
```

Now, **we can interact with our blog!**

Creating a post
```bash
curl -X POST -H "Content-Type: application/json" -d '{
    "title": "New blog!",
    "description": "lets do this"
}' "http://localhost:8080/api/post"
```

Listing all posts
```bash
curl -X GET "http://localhost:8080/api/post/"
```

Get one post
```bash
curl -X GET "http://localhost:8080/api/post/1"
```

Updating a post
```bash
curl -X PUT -H "Content-Type: application/json" -d '{"title": "lets change the title."}' "http://localhost:8080/api/post/1"
```

Delete a post
```bash
curl -X DELETE "http://localhost:8080/api/post/1"
```

#### Using Hooks
Hooks are really useful to add validations in different moments of your application. Hook is a class that connect with your model and will be executed:

* before save the model
* after the model be saved
* before the model be deleted

Now, let's use add a [Hook](http://localhost:8000/documentation/#hooks), to prevent that a post can be created without a title.

```python
class PostHook(Hook):

    def before_save(self, post):
        if not post.title:
            raise Exception('Title cannot be None')

        return True
```

To connect this hook with the Post endpoint, you just need add one line in your model
```python
@endpoint('/user')
class Post(DBModel):
    hooks = [PostHook]  # add this line

    title = peewee.CharField()
    description = peewee.TextField()

```

#### Using Actions

Now, lets add another endpoint that change the title of a Post to upper case. This is very simple example, but you can use Actions basically to every action (oh no, really?) that your model has. We could write an Action that deactivate a post or set a favorite flag to true.


```python
from ray.actions import ActionAPI, action

class ActionPost(ActionAPI):
    __model__ = Post

    @action("/<id>/upper")
    def upper_case(self, model_id):
        post = Post.get(id=model_id)
        post.update({'title': post.title.upper(), 'id': model_id})

```


#### Using Authentication

Ray has a built-in module of Authentication. You [can get more details of it here](https://rayframework.github.io/site/documentation/#authentication). Basically, we just need to override the authenticate method. Since we don't have a User table to check if the data of user are valid, let's have a hard coded login.

```python
from ray.authentication import Authentication


class MyAuth(Authentication):

    @classmethod
    def authenticate(cls, username, password):
        return username == 'ray' and password == 'framework'
```

Now, update your model to make sure that it will be under the authentication protection.
```python
@endpoint('/person', authentication=MyAuth)
class PersonModel(ModelInterface):
    pass
```

Now, you need to login in the application to get acess to the Post endpoint.
```bash
curl -X PUT -H "Content-Type: application/json" -d '{
    "username": "ray",
    "password": "framework"
}' "http://localhost:8080/api/_login"
```

#### Using Shields

With Shields, you can protect your endpoints. Let's imagine that we have a lot of users in your application, but just the user with username 'ray' can update a Post. Let's do this:

```python
class PostShield(Shield):
    __model__ = Post

    def put(self, info):
        return info['username'] == 'ray'
```


#### Done!

Now, you already know the main features of Ray, from these features you can develop anything that you want!
