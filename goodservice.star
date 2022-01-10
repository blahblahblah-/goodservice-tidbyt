load("render.star", "render")
load("time.star", "time")
load("http.star", "http")

STOP_ID = "M16"
GOOD_SERVICE_STOPS_URL_BASE = "https://goodservice.io/api/stops/"
GOOD_SERVICE_ROUTES_URL = "https://goodservice.io/api/routes/"

ABBREVIATIONS = {
  " - ": "–",
  "Center": "Ctr",
  "Metropolitan": "Metrop",
}

def condense_name(name):
  for key in ABBREVIATIONS:
    name = name.replace(key, ABBREVIATIONS[key])
  split_name = name.split("–")
  if len(split_name) > 1 and ("St" in split_name[1] or "Av" in split_name[1] or "Sq" in split_name[1] or "Blvd" in split_name[1]) and (split_name[0] != "Far Rockaway"):
    return split_name[1]
  return split_name[0]

def main():
  routes_req = http.get(GOOD_SERVICE_ROUTES_URL)
  if routes_req.status_code != 200:
      fail("goodservice routes request failed with status %d", routes_req.status_code)

  stop_req = http.get(GOOD_SERVICE_STOPS_URL_BASE + STOP_ID)
  if stop_req.status_code != 200:
      fail("goodservice stop request failed with status %d", stop_req.status_code)

  stops_req = http.get(GOOD_SERVICE_STOPS_URL_BASE)
  if stops_req.status_code != 200:
      fail("goodservice stops request failed with status %d", stops_req.status_code)

  directions = ["north", "south"]
  ts = time.now().unix
  blocks = []

  for dir in directions:
    upcoming_routes = {
      "north": [],
      "south": [],
    }
    dir_data = stop_req.json()["upcoming_trips"].get(dir)
    if not dir_data:
      continue

    for trip in dir_data:
      matching_route = None
      for r in upcoming_routes[dir]:
        if r["route_id"] == trip["route_id"] and r["destination_stop"] == trip["destination_stop"]:
          matching_route = r
          break

      if matching_route:
        if len(matching_route["times"]) == 1:
          matching_route["times"].append(trip["estimated_current_stop_arrival_time"])
        else:
          continue
      else:
        upcoming_routes[dir].append({"route_id": trip["route_id"], "destination_stop": trip["destination_stop"], "times": [trip["estimated_current_stop_arrival_time"]] })

    # sorted_routes = sorted(upcoming_routes[dir], key=lambda r: r["times"][0])

    for dir in directions:
      for r in upcoming_routes[dir]:
        if len(blocks) > 0:
          if dir == "south" and r == upcoming_routes[dir][0]:
            blocks.append(render.Box(width=64, height=1, color="#aaa"))
          else:
            blocks.append(render.Box(width=64, height=1, color="#333"))

        selected_route = routes_req.json()["routes"][r["route_id"]]
        route_color = selected_route["color"]
        text_color = selected_route["text_color"] if selected_route["text_color"] else "#fff"
        destination = None

        for s in stops_req.json()["stops"]:
          if s["id"] == r["destination_stop"]:
            destination = condense_name(s["name"])
            break

        first_eta = (int(r["times"][0]) - ts) / 60
        if first_eta < 1:
          text = "due"
        else:
          text = str(int(first_eta))

        if len(r["times"]) == 1:
          text = text + " min"
        else:
          second_eta = (int((r["times"][1]) - ts) / 60)
          if second_eta < 1:
            text = text + ", due"
          else:
            text = text + ", " + str(int(second_eta)) + " min"

        blocks.append(render.Padding(
          pad=(0, 0, 0, 1),
          child=render.Row(
            main_align="start",
            cross_align="center",
            children=[
              render.Padding(
                pad=(1, 0, 1, 0),
                child=render.Circle(
                  color=route_color,
                  diameter=11,
                  child=render.Box(
                    padding=1,
                    height=11,
                    width=11,
                    child=render.Text(
                      content=selected_route["name"] if selected_route["name"] != "SIR" else "SI",
                      color=text_color,
                      height=8,
                    )
                  )
                )
              ),
              render.Column(
                children=[
                  render.Text(destination),
                  render.Text(content=text, font="tom-thumb", color="#f2711c"),
                ]
              )
            ]
          )
      ))

  return render.Root(
    child=render.Marquee(
      height=32,
      offset_start=32,
      offset_end=0,
      scroll_direction="vertical",
      child=render.Column(
        children=blocks
      )
    )
  )