var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "I Love Khirsca and Kaiden");

app.Run();
