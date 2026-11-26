"""Selenium end-to-end tests. Run against a live app:
    BASE_URL=http://localhost:8000 pytest tests/e2e -v
Skipped automatically when BASE_URL is unset or Chrome/Selenium isn't available."""
import os
import uuid

import pytest

BASE_URL = os.getenv("BASE_URL")
pytestmark = pytest.mark.skipif(not BASE_URL, reason="set BASE_URL to run browser tests")


@pytest.fixture(scope="module")
def browser():
    webdriver = pytest.importorskip("selenium.webdriver")
    opts = webdriver.ChromeOptions()
    for arg in ("--headless=new", "--no-sandbox", "--disable-dev-shm-usage"):
        opts.add_argument(arg)
    try:
        driver = webdriver.Chrome(options=opts)
    except Exception as exc:  # no Chrome installed
        pytest.skip(f"Chrome not available: {exc}")
    yield driver
    driver.quit()


def test_home_page_renders(browser):
    from selenium.webdriver.common.by import By

    browser.get(BASE_URL)
    assert browser.title == "Taskboard"
    assert browser.find_element(By.ID, "title").text == "Taskboard"


def test_flag_badge_matches_api(browser):
    import requests
    from selenium.webdriver.common.by import By

    enabled = requests.get(f"{BASE_URL}/api/flags", timeout=5).json()["priority_tasks"]
    browser.get(BASE_URL)
    assert browser.find_element(By.ID, "flag-priority").text == ("ON" if enabled else "OFF")


def test_new_task_appears_on_page(browser):
    import requests
    from selenium.webdriver.common.by import By

    title = f"e2e-{uuid.uuid4().hex[:6]}"
    assert requests.post(f"{BASE_URL}/api/tasks", json={"title": title}, timeout=5).status_code == 201
    browser.get(BASE_URL)
    items = [li.text for li in browser.find_elements(By.CSS_SELECTOR, "#tasks li")]
    assert title in items
