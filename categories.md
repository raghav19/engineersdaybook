---
layout: page
title: All Categories
---

# Posts by Category

Browse all posts organized by their categories:

{% assign all_categories = site.categories | sort %}
{% for category in all_categories %}
  {% assign category_name = category[0] %}
  {% assign category_posts = category[1] %}
  
## {{ category_name | capitalize }}

<ul>
  {% for post in category_posts %}
    <li>
      <span>{{ post.date | date: site.theme_config.date_format }}</span>
      {% if site.theme_config.lowercase_titles == true %}
      <a href="{{ post.url | relative_url }}">{{ post.title | downcase }}</a>
      {% else %}
      <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
      {% endif %}
    </li>
  {% endfor %}
</ul>

[View {{ category_name }} archive](archives/{{ category_name }}-archive.html)

{% endfor %}

---

[← Back to home]({{ "/" | relative_url }})