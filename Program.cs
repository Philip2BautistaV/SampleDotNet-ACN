var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "1st testing for today");

app.Run();
