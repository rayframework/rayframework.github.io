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

After that, create an *app.py* file with our Model, Post.

```python
# app.py

import peewee
from ray_peewee.all import PeeweeModel
from ray.wsgi.wsgi import application
from ray.endpoint import endpoint


database = peewee.SqliteDatabase("example.db")


class DBModel(PeeweeModel):
    class Meta:
        database = database


@endpoint("/user")
class Post(DBModel):
    title = peewee.CharField()
    description = peewee.TextField()

```

Now, lets run our application and check if it's everything alright.

```bash
ray up --wsgifile=app.py
```

Done! Now, **we already can interact with our blog!**

```bash
curl -X POST https://localhost:8080/api/user {"title": "Our first POST!", "description": "YEY!"}
```
