# Needs to be at the root of the project
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', '__PROJECT_NAME__.settings')
app = Celery('__PROJECT_NAME__')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()