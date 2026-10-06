using System.Net;
using System.Net.Mail;
using System.Net.Mime;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;

public class EmailService
{
    private readonly string smtpServer;
    private readonly int smtpPort;
    private readonly string smtpUser;
    private readonly string smtpPass;

    public EmailService(IConfiguration configuration)
    {
        smtpServer = configuration["EmailSettings:SmtpServer"];
        smtpPort = int.Parse(configuration["EmailSettings:SmtpPort"]);
        smtpUser = configuration["EmailSettings:SmtpUser"];
        smtpPass = configuration["EmailSettings:SmtpPass"];
    }

    public async Task<bool> SendEmailAsync(string toEmail, string subject, string body)
    {
        return await SendEmailWithLogoAsync(toEmail, subject, body, null);
    }

    public async Task<bool> SendEmailWithLogoAsync(
        string toEmail, string subject, string body, string? logoFilePath)
    {
        try
        {
            using (var client = new SmtpClient(smtpServer, smtpPort))
            {
                client.UseDefaultCredentials = false;
                client.Credentials = new NetworkCredential(smtpUser, smtpPass);
                client.EnableSsl = true;
                client.DeliveryMethod = SmtpDeliveryMethod.Network;

                var mailMessage = new MailMessage
                {
                    From = new MailAddress(smtpUser),
                    Subject = subject,
                    IsBodyHtml = true,
                };
                mailMessage.To.Add(toEmail);

                if (!string.IsNullOrWhiteSpace(logoFilePath) && System.IO.File.Exists(logoFilePath))
                {
                    var htmlView = AlternateView.CreateAlternateViewFromString(body, null, "text/html");
                    var logoResource = new LinkedResource(logoFilePath)
                    {
                        ContentId = "company_logo_cid",
                        TransferEncoding = TransferEncoding.Base64
                    };
                    string ext = System.IO.Path.GetExtension(logoFilePath).ToLowerInvariant();
                    logoResource.ContentType = new ContentType(ext switch
                    {
                        ".png" => "image/png",
                        ".jpg" => "image/jpeg",
                        ".jpeg" => "image/jpeg",
                        ".gif" => "image/gif",
                        _ => "image/png"
                    });
                    htmlView.LinkedResources.Add(logoResource);
                    mailMessage.AlternateViews.Add(htmlView);
                    Console.WriteLine($"[EmailService] Logo embedded as CID: {logoFilePath}");
                }
                else
                {
                    mailMessage.Body = body;
                    Console.WriteLine("[EmailService] No logo attached.");
                }

                await client.SendMailAsync(mailMessage);
            }

            var p = new Dapper.DynamicParameters();
            p.Add("@TOAddress", toEmail);
            p.Add("@TOSubject", subject);
            p.Add("@MailBody", body);
            p.Add("@status", 1);
            p.Add("@ErrorMsg", string.Empty);
            HRMSWebAPI.Helper.DataBaseFactory.QuerySP("SAL_Email_Log_Ins", p, "GetAll");
            return true;
        }
        catch (Exception ex)
        {
            var p = new Dapper.DynamicParameters();
            p.Add("@TOAddress", toEmail);
            p.Add("@TOSubject", subject);
            p.Add("@MailBody", body);
            p.Add("@status", 0);
            p.Add("@ErrorMsg", ex.Message);
            HRMSWebAPI.Helper.DataBaseFactory.QuerySP("SAL_Email_Log_Ins", p, "GetAll");
            Console.WriteLine($"Error sending email: {ex.Message}");
            return false;
        }
    }
}