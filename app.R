# Load libraries
library(dash)
library(dashHtmlComponents)
library(dashCoreComponents)
library(dashBootstrapComponents)
library(dashTable)
library(dplyr)
library(purrr)
library(stringr)
library(devtools)
library(here)



# Load custom functions and data
devtools::load_all(".")

coi_data <- arrow::read_feather(here("data-processed/filtered_hierarchy_data.feather"))
tbl_col_ids <- c("NAME", "LEVEL", "CCTL")
tbl_col_names <- c("Name", "Level", "Country of Control")
# Load CSS Styles
css <- custom_css()

# bnames <- as.character(unique(forcats::fct_c(h2h::combined_data$BusinessName,
#                   h2h::combined_data$BusinessTradeName)))
# bnames <- bnames[!is.na(bnames) & !bnames == ""]
# bnames <- c(head(bnames, 20))

# app layout
app <- Dash$new(external_stylesheets = dbcThemes$BOOTSTRAP)
app$title("CoV Business Risk Dashboard")
app$layout(
  dbcContainer(
    list(
      htmlH1("Company Risk Dashboard",
        style = css$header
      ),
      dbcRow(
        list(
          dbcCol( # INPUT CONTROLS
            id = "options-panel",
            style = css$box,
            md = 4,
            list(
              htmlBr(),
              dbcLabel("Company Name:"),
              # dccDropdown(id = "input_bname",
              #             options = map(bnames, ~ list(label = ., value = .)),
              #             value = "Gyoza Bar Ltd",
              #             clearable = TRUE,
              #             searchable = FALSE # TODO: test this out for speed
              dccInput(
                id = "input_bname",
                # value = "Listel Canada Ltd"         # for testing
                # value = "Westfair Foods Ltd"
                value = "Gyoza Bar Ltd"           # for testing
                # value = "VLC Leaseholds Ltd"      # for testing
              ),
              htmlBr(),
              dbcLabel("Address:"),
              dccInput(),
              htmlHr()
            )
          ),
          htmlBr(),
          dbcCol( # PLOTTING PANEL
            list(
              dccTabs(id = "tabs", children = list(
                dccTab(label = "License History", children = list(
                  htmlDiv(
                    list(
                      dbcCard(
                        list(
                          dbcAlert(
                            #is_open = risk_score(bname) > 2,
                            id = "card_score"
                          ),
                          dbcCardBody(
                            htmlDiv(id = "network_div", children = list(
                              htmlIframe(
                                height = 500, width = 500,
                                id = "network_plot",
                                style = css$noborder
                              )
                            ))
                          )
                        )
                      ),
                      dbcCard(
                        list(
                          dbcCardBody()
                        )
                      )
                    )
                  )
                )),
                dccTab(label = "Business Details", children = list(
                  htmlDiv(
                    list(
                      htmlDiv(list(
                      dbcCard(
                        list(
                          dbcCardHeader('Business Summary'),
                          dbcCardBody(list(
                            # Business Type Table
                            dashDataTable(
                              id = 'co-type',
                              columns = list(label = "Primary Business Type", value = "PrimaryBusinessType"),
                              page_size = 10,
                              style_cell = css$tbl_fonts,
                              style_header = css$tbl_hrow,
                              style_cell_conditional = css$bs_tbl_align,
                              style_as_list_view = TRUE
                            )
                          )
                        )
                      ))), style=css$horiz_split),
                      htmlDiv(list(
                      dbcCard(
                        list(
                          dbcCardHeader("Company Size"),
                          dbcCardBody(list(
                            dccGraph(id = "num_emp_plot")
                          ))
                        )
                      )
                      ), style=css$horiz_split),
                    htmlDiv(list(
                      dbcCard(
                        list(
                          dbcCardHeader('Inter-corporate Relationships'),
                          dbcCardBody(
                            list(
                            dashDataTable(
                              id = "related_co_table",
                              page_size = 10,
                              data = df_to_list(coi_data),
                              columns = map2(tbl_col_ids, tbl_col_names, function(col, col2) list(id = col, name = col2)),
                              style_cell_conditional = css$rc_tbl_colw,
                              fixed_columns = css$fixed_headers,
                              css = css$tbl_ovrflw,
                              style_data = css$ovrflow_ws,
                              style_as_list_view = TRUE,
                              style_header = css$tbl_hrow,
                              style_cell = css$tbl_fonts
                            ))
                          )
                        )
                      )
                    ))),
                  )
                ))
              ))
            ),
          )
        ),
        style = css$no_left_pad
      ),
      htmlBr()
    )
  )
)

# update related companies table on "Business Details" tab
app$callback(
  list(output("related_co_table", "data")),
  list(input("input_bname", "value")),
  function(input_value) {
    if (vbr %>%
      filter(BusinessName == input_value) %>%
      select("PID") %>%
      unique() %>% nrow() < 1) {
      # if no related companies found, return empty list.
      data <- list()
    }
    else {
      selected_PID <- vbr %>%
        filter(BusinessName == input_value) %>%
        select("PID") %>%
        unique()
      data <- df_to_list(coi_data %>%
        filter(PID == selected_PID[[1]] & LEVEL > 0) %>%
        arrange(LEVEL))
    }
    list(data)
  }
)

# update business summary on "Business Details" tab
app$callback(
  list(
    output("co-type", "data"),
    output("co-type", "columns")
  ),
  list(input("input_bname", "value")),
  function(input_value) {
    data <- vbr %>%
      filter((BusinessName == input_value)) %>%
      arrange(desc(FOLDERYEAR)) %>%
      top_n(n = 1, wt = FOLDERYEAR) %>%
      select(BusinessType) %>%
      unique() %>%
      df_to_list()
    columns <- c("BusinessType") %>% purrr::map(function(col) list(name = "Primary Business Type", id = col))
    list(data, columns)
  }
)

# plot number of employees for industry on "Business Details" tab
app$callback(
  output("num_emp_plot", "figure"),
  list(input("input_bname", "value")),
  function(input_value) {
    emp_plot <- vbr %>%
      mutate(FOLDERYEAR = formatC(vbr$FOLDERYEAR, width = 2, format = "d", flag = "0")) %>%
      filter((BusinessName == input_value) & (FOLDERYEAR <= format(Sys.Date(), "%y"))) %>%
      group_by(FOLDERYEAR, LicenceNumber) %>%
      summarise(NumberofEmployees = mean(NumberofEmployees))

    # if no data available
    if (emp_plot %>% tidyr::drop_na() %>% nrow() < 1) {
      emp_plot <- ggplot2::ggplot() +
        ggplot2::geom_text() +
        ggplot2::theme_void() +
        ggplot2::annotate("text", label = "No data available.", x = 2, y = 15, size = 8) +
        ggplot2::theme(
          panel.grid.major = ggplot2::element_blank(),
          panel.grid.minor = ggplot2::element_blank()
        )
      return(plotly::ggplotly(emp_plot))
    }
    # if data available
    else {
      emp_plot <- emp_plot %>% ggplot2::ggplot(ggplot2::aes(
        x = FOLDERYEAR,
        y = NumberofEmployees
      )) +
        ggplot2::stat_summary(fun = "sum", geom = "bar", fill = "royalblue4") +
        ggplot2::labs(
          y = "Number of Employees Reported",
          x = "Year"
        ) +
        ggplot2::scale_x_discrete(
          labels = function(x) paste0("20", x),
          drop = FALSE,
          limits = factor(seq(
            vbr %>% select(FOLDERYEAR) %>% min(),
            format(Sys.Date(), "%y")
          ))
        ) +
        ggplot2::scale_y_continuous(expand = c(0, 0.1)) +
        ggplot2::theme_bw() +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = 90),
          panel.background = ggplot2::element_rect(fill = "white"),
          panel.grid.minor = ggplot2::element_blank(),
          panel.grid.major.x = ggplot2::element_blank()
        )
      return(plotly::ggplotly(emp_plot, tooltip = "y"))
    }
  }
)


# update network plot on "License History" tab
app$callback(
  output("network_plot", "srcDoc"),
  list(
    input("input_bname", "value")
  ),
  memoise::memoize(function(x) {
    viz <- viz_graph(x)

    # workaround
    tempfile <- here::here("network.html")
    htmlwidgets::saveWidget(viz, file = tempfile)
    paste(readLines(tempfile), collapse = "")
  })
)

app$callback(
  list(
    output("card_score", "children"),
    output("card_score", "color")
  ),
  list(
    input("input_bname", "value")
  ),
  memoise::memoize(function(bname) {
    r <- calc_risk(bname)
    pr <- profile_risk(bname)

    lev <- case_when(r <= 1 ~ "low risk",
                     r <= 3 ~ "medium risk",
                     TRUE ~ "high risk")

    color_back <- case_when(r <= 1 ~ "green",
                     r <= 3 ~ "yellow",
                     TRUE ~ "red")

    msg <- c()
    msg[1] <- if_else(pr$missingdata, "has a lot of missing data", NA_character_)
    msg[2] <- if_else(pr$recent, "does not have a long history", NA_character_)
    msg[3] <- if_else(pr$foreign, "is not located in Canada", NA_character_)
    msg[4] <- if_else(pr$status, "is inactive or shut", NA_character_)
    msg <- glue::glue_collapse(na.omit(msg), sep = ", ", last = " and ")

    list(str_glue("Risk Score: {r} / 4 ({lev}). This business {msg}."), color_back)
    })
)

if (Sys.getenv("DYNO") == "") {
  app$run_server(
    debug = FALSE,
    dev_tools_hot_reload = FALSE
  )
} else {
  app$run_server(host = "0.0.0.0")
}
