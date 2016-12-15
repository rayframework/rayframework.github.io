
# Features

## Easy APIs

Create a model and then decorated it with the endpoint decorator.
```python
from ray.endpoint import endpoint
from ray_sqlalchemy import AlchemyModel
from sqlalchemy import Column, Integer, String

Base = declarative_base()

@endpoint('/user')
class UserModel(AlchemyModel):
    name = StringProperty()
    age = IntegerProperty()
```

Now, you have the http methods to interact with your model using the urls:

|HTTP Verb | Path | Description          |
|--------- | ---- | -------------------- |
|  GET     | /api/user| List all users       |
|  GET     | /api/user/{id} | Get one user   |
|  POST    | /api/user| Create an user       |
|  PUT     | /api/user/{id} | Update an user |
|  DELETE  | /api/user/{id} | Delete an user |

Also, Ray provides a simple way to your search for records. Check it how to do it:
```bash
curl -X GET "http://localhost:8081/api/user?name=john&age=40"
```

By the default, all columns of your Model can be used to filter.

## Hooks
Hooks are really useful to add validations in different moments of your application. Hook is a class that connect with your model and will be executed **before save the model, after the model be saved or before the model be deleted**.

```python
from ray.hooks import DatabaseHook

class AgeValidationHook(DatabaseHook):

    def before_save(self, user):
        if user.age < 18:
            raise Exception('The user must have more than 18 years')
        return True

@endpoint('/user')
class UserModel(AlchemyModel):
    hooks = [AgeValidationHook]

    name = StringProperty()
    age = IntegerProperty()
```
Available Hooks:

* `before_delete` method
* `before_save` method
* `after_save` method

Then, if you call the .put() method of UserModel and the user doesn't has age bigger than 18, an Exception will be raised.

## Actions
Actions provide a simple way to you create behavior in your models through your api. After writing the code bellow, you can use the url `/api/user/<user_id>/activate` to invoke the activate_user method.

When you create an action method, the parameters are:

 * `model_id`: corresponds to the `<user_id> passed in the url. If there isn't an argument sent in the url, the model_id parameter will be None.
 * `parameters`: This parameter will be filled with the json posted when this url were called with a POST or a PUT. However, if you use GET or DELETE the query params in the url will fill the parameters.

As an example:

When the url `/api/user/1/activate?name=john` is called with GET. The parameters will be: `model_id = 1` and parameters a dict `{'name': 'john'}`.


```python
from ray.actions import Action, action

class ActionUser(Action):
    __model__ = UserModel

    @action("/activate")
    def activate_user(self, model_id, parameters):
        user = storage.get(UserModel, model_id)
        user.activate = True
        storage.put(user)
```

#### Action with Authentication
If you wanna that the Actions method can only be called when the user is authenticated, use the `authentication=True` parameters in the `@action` decorator.

Example:
```python
from ray.actions import Action, action

class ActionUser(Action):
    __model__ = UserModel

    @action("/activate", authentication=True)
    def activate_user(self, model_id, parameters):
        pass
```

## Authentication

Ray has a built-in authentication module. To use it, you just need to inherit the Authentication class and implement the method `authenticate` and the method `salt_key`. In the `authenticate` method, you'll check the data in the database and then return if the user can login or not. Remember that this method must return a dictionary if the authentication succeeded.
PS: You can create one (and just one) class that inherit from the Authentication class.
In the `salt_key` method you should return a salt string used to compose the authentication token.

Also, the Authentication expects that you implement:

 * `expiration_time`: Indicate the time (*in minutes*) that token sent to the client will be valid. If the user don't talk to the API for more than the `expiration_time`, the next time he hit the API he will get a forbidden.


```python
from ray.authentication import Authentication, register

@register
class MyAuth(Authentication):

    expiration_time = 5  # in minutes

    @classmethod
    def authenticate(cls, login_data):
        user = User.query(User.username == login_data['username'],
                          User.password == login_data['password']).one()
        return {'username': 'ray'} if user else None

    @classmethod
    def salt_key(cls):
        return 'salt_key'
```

If you want protect all the operations in this endpoint, you can just add this:
```python
@endpoint('/person', authentication=MyAuth)
class PersonModel(ModelInterface):
    pass
```

After protect your endpoint via an Authentication, you will need to be logged in to don't get a 403 status code. To do this:

#### Login
```bash
curl -X POST -H "Content-Type: application/json" '{"username": "username", "password": "password"}' "http://localhost:8080/api/_login"
```

#### Logout
```bash
curl -X GET "http://localhost:8080/api/_logout"
```

## Shields
Ray has an option to you protect just some HTTP methods of your endpoint: using Shields. How it works? You inherit from the Shield class and implement just the http method that you *want to protect*.

```python
class PersonShield(Shield):
    __model__ = PersonModel

    def get(self, user_data, model_id, parameters):
        return user_data['profile'] == 'admin'

    # def put(self, user_data, model_id, parameters): pass

    # def post(self, user_data, model_id, parameters): pass

    # def delete(self, user_data, model_id, parameters): pass
```

This shield protects the GET method of /api/person. The parameter *user_data* in the get method on the shield, is the dictionary returned on your Authentication class. So, all Shields's methods receive this parameter. When you overwrite a method, Ray will assume that method is under that Shield protection.

### Shields with Actions
If you wanna to protect an action you can do this with a Shield. To do this, you just need to implement a @staticmethod method in your Shield, *that doesnt has one of these names: get, delete, post or put*.
If this Action is not used by an authenticated user, the parameter `user_data` in your Shield's method will be None.
The parameters `user_id` and `model_id` follow the same rule that the Actions.

```python

class UserShield(Shield):
    __model__ = UserModel

    @staticmethod
    def protect_enable(user_data, model_id, parameters):
        return user_data['profile'] == 'admin'


class ActionUser(Action):
    __model__ = UserModel

    @action('/enable', protection=UserShield.protect_enable)
    def enable_user(self, model_id):
        user = session.get_user()
        user.enabled = True
        user.save()
```

## Serving static files
Ray uses bottle under the hood, so you can use bottle to serve your static files. However, this is only for **development enviroment**. In production enviroment, you should use nginx, apache or something like that to serve your static files.

Serve your static files just adding:
```python
from bottle import static_file
@application.route('/static/<filepath:path>')
def server_static(filepath):
    return static_file(filepath, root='static')
```

## Running the application
To run a Ray application, you just need to import `from ray.wsgi.wsgi import application` and then, run:
```bash
python app.py # the name of the file which imported the application variable
```
