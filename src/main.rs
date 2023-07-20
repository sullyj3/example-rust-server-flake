use actix_web::{web, App, HttpServer};

fn config(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/").to(|| async { "Hello Nixers!\n" }));
    cfg.service(web::resource("/rust").to(|| async { "Hello Nixers!\n" }));
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let default_port: String = "8080".to_string();
    let port: String = std::env::var("RUST_PORT")
        .unwrap_or(default_port);

    let addr = format!("0.0.0.0:{}", port);
    println!("Starting server at {}", addr);
    HttpServer::new(|| App::new().configure(config))
        .bind(addr)?
        .run()
        .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::dev::Service;
    use actix_web::{http, test, App, Error};

    #[actix_rt::test]
    async fn test() -> Result<(), Error> {
        let mut app = test::init_service(App::new().configure(config)).await;

        let resp = app
            .call(test::TestRequest::get().uri("/").to_request())
            .await
            .unwrap();

        assert_eq!(resp.status(), http::StatusCode::OK);

        let body = match resp.response().body().as_ref() {
            Some(actix_web::body::Body::Bytes(bytes)) => bytes,
            _ => panic!("Response error"),
        };

        assert_eq!(body, "Hello Nixers!\n");

        Ok(())
    }
}
