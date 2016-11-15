# Getting Started


## Building our first application with Ray

Let's see how easy is build an Evernote-like app using **Ray**!

To do this, we will use the Peewee ORM, which Ray is absolutely compatible (as well with SQLAlchemy and Google App Engine).

Install Peewee and Ray and the Ray plugin to integrated with the ORM.

TL;DR: You can check the [entire code here](https://github.com/felipevolpone/ray/blob/master/examples/simple_note/app.py)

PS: This code is just to provide **an example** of how to use Ray.

```bash
pip install peewee
pip install ray_framework
pip install ray_peewee
```

After that, create an *app.py* file with our models: Notebook and Note.

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


@endpoint('/notebook')
class Notebook(DBModel):
    title = peewee.CharField()
    update_at = peewee.BigIntegerField()
    active = peewee.BooleanField(default=True)


@endpoint('/note')
class Note(DBModel):
    title = peewee.CharField()
    update_at = peewee.BigIntegerField()
    content = peewee.TextField()
    notebook = peewee.ForeignKeyField(Notebook)


if __name__ == '__main__':
    database.connect()
    database.create_tables([Notebook, Note], safe=True)
    database.close()
    application.run(debug=True, reloader=True)

```

Run the application.

```bash
python app.py
```

Now, **we can interact with our app!**

* Creating a notebook
```bash
curl -X POST -H "Content-Type: application/json" '{"title": "new ideas"} ' "http://localhost:8080/api/notebook"
```

* Creating a note
```bash
curl -X POST -H "Content-Type: application/json" '{"title": "new ideas", "notebook": "1"} ' "http://localhost:8080/api/note"
```

* Listing all notebooks
```bash
curl -X GET "http://localhost:8080/api/notebook/"
```

* Searching for a record
```bash
curl -X GET "http://localhost:8080/api/notebook?title=new ideias"
```

* Get one notebook
```bash
curl -X GET "http://localhost:8080/api/notebook/1"
```

* Updating a notebook
```bash
curl -X PUT -H "Content-Type: application/json" -d '{"title": "lets change the title."}' "http://localhost:8080/api/notebook/1"
```

* Delete a notebook
```bash
curl -X DELETE "http://localhost:8080/api/notebook/1"
```

#### Using Hooks
Hooks are useful to add validations in different moments of your application. Hook is a class that connect with your model and will be executed:

* before save the model (the `before_save` method)
* after the model be saved (the `after_save` method)
* before the model be deleted (the `before_delete` method)

Now, let's use add a [Database Hook](http://localhost:8000/documentation/#hooks), to add some validations.

```python
from ray.hooks import DatabaseHook

class CreatedAtBaseHook(DatabaseHook):

    def before_save(self, model):
        model.update_at = int(datetime.now().strftime('%s')) * 1000
        return True


class NoteHook(CreatedAtBaseHook):

    def before_save(self, note):
        super(NoteHook, self).before_save(note)

        if not note.title:
            raise Exception('Title cannot be None')

        if not note.notebook_id:
            raise Exception('A note only exists inside a notebook')

        return True


class NotebookHook(CreatedAtBaseHook):

    def before_save(self, notebook):
        super(NotebookHook, self).before_save(notebook)

        if not notebook.title:
            raise Exception('Title cannot be None')
        
        #notebook.owner = dict_to_model(User, SimpleNoteAuthentication.get_logged_user())
        return True
```

To connect this hook with the Notebook endpoint, you just need add one line in your model
```python
@endpoint('/notebook')
class Notebook(DBModel):
    hooks = [NotebookHook]

@endpoint('/note')
class Note(DBModel):
    hooks = [NoteHook]
```

#### Using Authentication

Ray has a built-in module of Authentication. You [can get more details of it here](https://rayframework.github.io/site/documentation/#authentication). Basically, we just need to override the authenticate method. 

```python
from ray.authentication import Authentication, register

@register
class SimpleNoteAuthentication(Authentication):

    expiration_time = 5  # in minutes

    @classmethod
    def authenticate(cls, login_data):
        users = User.select().where(User.username == login_data['username'],
                                    User.password == login_data['password'])
        if not any(users):
            raise Exception('Wrong username or/and password')

        return users[0].to_json()

    @classmethod
    def salt_key(cls):
        return 'anything'
```

Also, let's create a User model and add the owner field in the Notebook model.
```python
class UserHook(DatabaseHook):

    def before_save(self, user):
        users_same_username = (User.select()
                                   .where(User.username == user.username))
        if any(users_same_username):
            raise Exception('The username is unique')

        return True


class User(DBModel):
    hooks = [UserHook]

    username = peewee.CharField()
    password = peewee.CharField()
    profile = peewee.CharField()


class Profile(object):
    ADMIN = 'admin'
    DEFAULT = 'default'
```

In the notebook endpoint, we'll use the authentication argument to say that this endpoint it's under the authentication module. This means that you only can call the notebook endpoints when the user is logged in.

```python
@endpoint('/notebook', authentication=SimpleNoteAuthentication)
class Notebook(DBModel):
    hooks = [NotebookHook]
    owner = peewee.ForeignKeyField(User)

@endpoint('/note', authentication=SimpleNoteAuthentication)
class Note(DBModel):
    hooks = [NoteHook]
```

In the end of your app.py file, add these lines, to create some mock users:
```python
if __name__ == '__main__':
    database.connect()
    database.create_tables([User, Notebook, Note], safe=True)
    User.create(username='admin', password='admin', profile=Profile.ADMIN)
    User.create(username='john', password='123', profile=Profile.DEFAULT)
    database.close()
    application.run(debug=True, reloader=True)

```

Now, you need to login in the application to get acess to the Post endpoint.
```bash
curl -X PUT -H "Content-Type: application/json" -d '{
    "username": "ray",
    "password": "framework"
}' "http://localhost:8080/api/_login"
```

#### Using Actions

Actions help you to extend your endpoints and add more behavior to your application. So, we'll create to actions to invite someone to our notebook and to deactivate a notebook.

```python

class MailHelper(object):

    @classmethod
    def send_email(self, to, message):
        # fake send email
        print('sending email to: %s with message: %s' % (to, message)) 


class NotebookActions(Action):
    __model__ = Notebook

    @action('/<id>/invite', authentication=True)
    def invite_to_notebook(self, notebook_id, parameters):
        to = parameters['user_to_invite']
        title = Notebook.select().where(Notebook.id == notebook_id)[0].title
        message = 'Help me build new stuff in this notebook: %s' % (title)
        MailHelper.send_email(to, message)

    @action('/<id>/deactivate', protection=NotebookShield.only_owner_can_deactivate, authentication=True)
    def deactivate(self, notebook_id, parameters):
        notebook = Notebook.select().where(Notebook.id == int(notebook_id))[0]
        notebook.active = False
        notebook.update()
```

Check that the `deactivate` method has the protection parameter pointing to a Shield. This is helpful when you wanna protect an Action. So, lets add the `only_owner_can_deactivate` method in our shield.

```python
class NotebookShield(Shield):
    __model__ = Notebook

    def delete(self, user_data, notebook_id, parameters):
        return user_data['profile'] == Profile.ADMIN

    @staticmethod
    def only_owner_can_deactivate(user_data, notebook_id, parameters):
        notebook = Notebook.select().where(Notebook.id == int(notebook_id))[0]
        notebook_json = model_to_dict(notebook, recurse=False)
        return user_data['id'] == notebook_json['owner']

```

#### Using Shields

With Shields, you can protect your endpoints. Let's imagine that only users with the admin profile can call the HTTP DELETE method of our notebook endpoint. To do that:

```python
class NotebookShield(Shield):
    __model__ = Notebook

    def delete(self, user_data, notebook_id, parameters):
        return user_data['profile'] == Profile.ADMIN
```


#### Done!
Now, you already know the main features of Ray, from these features you can develop anything that you want!

### The Entire code

```python

from playhouse.shortcuts import dict_to_model, model_to_dict  # peewee
import peewee

from datetime import datetime

from ray.authentication import Authentication, register
from ray.hooks import DatabaseHook
from ray.wsgi.wsgi import application
from ray.endpoint import endpoint
from ray_peewee.all import PeeweeModel
from ray.actions import Action, action
from ray.shield import Shield


database = peewee.SqliteDatabase('example.db')


class DBModel(PeeweeModel):
    class Meta:
        database = database


class MailHelper(object):

    @classmethod
    def send_email(self, to, message):
        # fake send email
        print('sending email to: %s with message: %s' % (to, message))


class UserHook(DatabaseHook):

    def before_save(self, user):
        users_same_username = (User.select()
                                   .where(User.username == user.username))
        if any(users_same_username):
            raise Exception('The username is unique')

        return True


class User(DBModel):
    hooks = [UserHook]

    username = peewee.CharField()
    password = peewee.CharField()
    profile = peewee.CharField()


@register
class SimpleNoteAuthentication(Authentication):

    expiration_time = 5  # in minutes

    @classmethod
    def authenticate(cls, login_data):
        users = User.select().where(User.username == login_data['username'],
                                    User.password == login_data['password'])
        if not any(users):
            raise Exception('Wrong username or/and password')

        return users[0].to_json()

    @classmethod
    def salt_key(cls):
        return 'anything'  # do it rightly here


class CreatedAtBaseHook(DatabaseHook):

    def before_save(self, model):
        model.update_at = int(datetime.now().strftime('%s')) * 1000
        return True


class NoteHook(CreatedAtBaseHook):

    def before_save(self, note):
        super(NoteHook, self).before_save(note)

        if not note.title:
            raise Exception('Title cannot be None')

        if not note.notebook_id:
            raise Exception('A note only exists inside a notebook')

        return True


class NotebookHook(CreatedAtBaseHook):

    def before_save(self, notebook):
        super(NotebookHook, self).before_save(notebook)

        if not notebook.title:
            raise Exception('Title cannot be None')

        notebook.owner = dict_to_model(User, SimpleNoteAuthentication.get_logged_user())
        return True


@endpoint('/notebook', authentication=SimpleNoteAuthentication)
class Notebook(DBModel):
    hooks = [NotebookHook]

    title = peewee.CharField()
    update_at = peewee.BigIntegerField()
    owner = peewee.ForeignKeyField(User)
    active = peewee.BooleanField(default=True)


@endpoint('/note', authentication=SimpleNoteAuthentication)
class Note(DBModel):
    hooks = [NoteHook]

    title = peewee.CharField()
    update_at = peewee.BigIntegerField()
    content = peewee.TextField()
    notebook = peewee.ForeignKeyField(Notebook)


class NotebookShield(Shield):
    __model__ = Notebook

    def delete(self, user_data, notebook_id, parameters):
        return user_data['profile'] == Profile.ADMIN

    @staticmethod
    def only_owner_can_deactivate(user_data, notebook_id, parameters):
        notebook = Notebook.select().where(Notebook.id == int(notebook_id))[0]
        notebook_json = model_to_dict(notebook, recurse=False)
        return user_data['id'] == notebook_json['owner']


class NotebookActions(Action):
    __model__ = Notebook

    @action('/<id>/invite', authentication=True)
    def invite_to_notebook(self, notebook_id, parameters):
        to = parameters['user_to_invite']
        title = Notebook.select().where(Notebook.id == notebook_id)[0].title
        message = 'Help me build new stuff in this notebook: %s' % (title)
        MailHelper.send_email(to, message)

    @action('/<id>/deactivate', protection=NotebookShield.only_owner_can_deactivate, authentication=True)
    def deactivate(self, notebook_id, parameters):
        notebook = Notebook.select().where(Notebook.id == int(notebook_id))[0]
        notebook.active = False
        notebook.update()


class Profile(object):
    ADMIN = 'admin'
    DEFAULT = 'default'


if __name__ == '__main__':
    database.connect()
    database.create_tables([User, Notebook, Note], safe=True)
    User.create(username='admin', password='admin', profile=Profile.ADMIN)
    User.create(username='john', password='123', profile=Profile.DEFAULT)
    database.close()
    application.run(debug=True, reloader=True)
```
